defmodule YouCongress.Councils do
  @moduledoc "Private ordered Councils: matching halls in order, with General as the final fallback."
  import Ecto.Query
  alias YouCongress.{Repo, Halls, Authors, PeopleLists}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Councils.{Council, List, PeopleListMember, PeopleList, Evaluator}
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote

  def get(author_id), do: Repo.get_by(Council, author_id: author_id) |> preload()
  defp preload(nil), do: nil

  defp preload(council) do
    council = Repo.preload(council, lists: [people_list: :members])

    lists =
      Enum.map(council.lists, fn list ->
        source = list.people_list
        available = PeopleLists.accessible?(source, %User{author_id: council.author_id})

        %{
          list
          | name: if(available, do: source.name, else: "Unavailable list"),
            available: available,
            list_owner_id: if(available, do: source.author_id),
            public: available && source.public,
            list_version: if(available, do: source.version),
            members:
              if(available,
                do: Enum.reject(source.members, &(&1.author_id == council.author_id)),
                else: []
              )
        }
      end)

    %{council | lists: lists}
  end

  def ensure(author_id) do
    Repo.transaction(fn ->
      # Keep saves serialized without blocking references to this author from
      # other Councils (memberships, delegations, and votes).
      Repo.one!(from a in Authors.Author, where: a.id == ^author_id, lock: "FOR NO KEY UPDATE")

      # Use the same lock order for saves and vote refreshes. When called inside
      # another transaction, both locks stay held until that transaction commits.
      council =
        Repo.one(from c in Council, where: c.author_id == ^author_id, lock: "FOR UPDATE")
        |> preload()

      case council do
        nil ->
          council = Repo.insert!(Council.changeset(%Council{}, %{author_id: author_id}))

          Enum.each(Enum.with_index(default_lists()), fn {attrs, index} ->
            source =
              PeopleLists.write!(%User{author_id: author_id}, nil, %{
                name: attrs.name,
                members: [],
                public: false
              })

            Repo.insert!(
              List.changeset(
                %List{},
                Map.merge(attrs, %{
                  council_id: council.id,
                  position: index,
                  people_list_id: source.id
                })
              )
            )
          end)

          council = get(author_id)
          fallback = Enum.find(council.lists, & &1.fallback)

          legacy =
            Repo.all(
              from d in "delegations",
                where: d.deleguee_id == ^author_id and d.delegate_id != ^author_id,
                select: d.delegate_id
            )

          if legacy != [] do
            council |> Ecto.Changeset.change(onboarding_completed: true) |> Repo.update!()

            PeopleLists.write!(%User{author_id: author_id}, fallback.people_list_id, %{
              version: fallback.list_version,
              members: Enum.map(legacy, &%{author_id: &1})
            })
          end

          get(author_id)

        council ->
          council
      end
    end)
  end

  def complete_onboarding(%User{} = user) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      {count, _} =
        Repo.update_all(
          from(c in Council, where: c.author_id == ^user.author_id),
          set: [onboarding_completed: true]
        )

      if count == 1, do: :ok, else: {:error, :not_found}
    end
  end

  def default_lists do
    Enum.map(
      [
        {"ai-governance", "AI governance"},
        {"impact-on-labor", "Impact on labor"}
      ],
      fn {slug, name} ->
        {:ok, hall} = Halls.get_or_create_by_name(slug)
        %{hall_id: hall.id, name: name, fallback: false}
      end
    ) ++ [%{hall_id: nil, name: "All statements", fallback: true}]
  end

  def save(user, attrs, opts \\ [])

  def save(%User{} = user, attrs, opts) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      result =
        Repo.transaction(fn ->
          {:ok, council} = ensure(user.author_id)

          if value(attrs, :version) != council.version, do: Repo.rollback(:stale)
          lists = value(attrs, :lists) || []
          validate_lists!(council, lists)
          keep_ids = Enum.map(lists, &value(&1, :id)) |> Enum.reject(&is_nil/1)

          Repo.delete_all(
            from l in List, where: l.council_id == ^council.id and l.id not in ^keep_ids
          )

          Enum.each(Enum.with_index(lists), fn {item, index} ->
            save_list!(council, item, index)
          end)

          council |> Ecto.Changeset.change(version: council.version + 1) |> Repo.update!()
          sync_legacy(council.author_id)
          saved = get(user.author_id)
          previous_versions = Map.new(council.lists, &{&1.people_list_id, &1.list_version})

          changed_sources =
            saved.lists
            |> Enum.filter(&(previous_versions[&1.people_list_id] != &1.list_version))
            |> Enum.map(& &1.people_list_id)

          affected_authors =
            Enum.uniq([user.author_id | PeopleLists.dependent_authors(changed_sources)])

          if Keyword.get(opts, :refresh) == :async do
            YouCongress.DelegationVotes.enqueue_council_refresh(affected_authors)
          end

          {saved, affected_authors}
        end)

      case result do
        {:ok, {council, affected_authors}} ->
          unless Keyword.get(opts, :refresh) == :async,
            do: PeopleLists.refresh_authors(affected_authors)

          YouCongress.Track.event("Council saved", user)
          {:ok, council}

        error ->
          error
      end
    end
  end

  def save(_, _, _), do: {:error, :forbidden}

  defp validate_lists!(council, lists) do
    unless is_list(lists) and Enum.all?(lists, &is_map/1), do: Repo.rollback(:invalid_lists)
    fallback = Enum.find(council.lists, & &1.fallback)
    ids = Enum.map(lists, &value(&1, :id)) |> Enum.reject(&is_nil/1)
    owned = Enum.map(council.lists, & &1.id)

    valid =
      lists != [] and length(lists) <= 20 and
        length(ids) == length(Enum.uniq(ids)) and
        Enum.all?(ids, &(&1 in owned)) and value(Elixir.List.last(lists), :id) == fallback.id and
        Enum.count(lists, &(value(&1, :id) == fallback.id)) == 1

    unless valid, do: Repo.rollback(:invalid_order)
  end

  defp save_list!(council, attrs, index) do
    existing = Enum.find(council.lists, &(&1.id == value(attrs, :id))) || %List{}
    hall_id = value(attrs, :hall_id)
    hall = if hall_id, do: Repo.get(Halls.Hall, hall_id)
    if hall_id && is_nil(hall), do: Repo.rollback(:invalid_hall)
    if existing.fallback && hall_id, do: Repo.rollback(:invalid_fallback)
    source = save_source!(council, existing, attrs, hall)

    existing
    |> List.changeset(%{
      council_id: council.id,
      hall_id: hall_id,
      people_list_id: if(source, do: source.id, else: existing.people_list_id),
      position: index
    })
    |> Repo.insert_or_update!()
  end

  defp save_source!(council, existing, attrs, hall) do
    source_id = value(attrs, :people_list_id) || existing.people_list_id
    source = if source_id, do: PeopleLists.get(source_id, %User{author_id: council.author_id})
    members = value(attrs, :members) || []
    name = source_name(attrs, source, hall)

    cond do
      is_nil(existing.id) && is_nil(source_id) ->
        PeopleLists.write!(%User{author_id: council.author_id}, nil, %{
          name: name,
          members: members,
          public: false
        })

      source_id != existing.people_list_id ->
        source || Repo.rollback(:unavailable_list)

      source && source_changed?(existing, name, members) ->
        update_owned_source!(council, source, existing, attrs, name, members)

      true ->
        source
    end
  end

  defp source_name(attrs, source, hall),
    do: value(attrs, :name) || (source && source.name) || default_name(hall)

  defp source_changed?(existing, name, members) do
    name != existing.name || normalized_members(members) != normalized_members(existing.members)
  end

  defp update_owned_source!(council, source, existing, attrs, name, members) do
    if source.author_id != council.author_id, do: Repo.rollback(:read_only_list)

    if council.author_id in Enum.map(members, &value(&1, :author_id)),
      do: Repo.rollback(:invalid_members)

    # Reusable lists can include their owner; their own Council ignores that entry.
    self_members = Enum.filter(source.members, &(&1.author_id == council.author_id))

    PeopleLists.write!(%User{author_id: council.author_id}, source.id, %{
      name: name,
      version: value(attrs, :list_version) || existing.list_version,
      members: members ++ self_members
    })
  end

  defp normalized_members(members),
    do:
      Enum.map(members, fn m ->
        {value(m, :author_id), value(m, :reason), value(m, :source_url)}
      end)

  defp default_name(nil), do: "All statements"
  defp default_name(hall), do: hall.name

  def validate_url(changeset) do
    Ecto.Changeset.validate_change(changeset, :source_url, fn :source_url, url ->
      case URI.new(url) do
        {:ok, %{scheme: scheme, host: host}}
        when scheme in ["https", "http"] and is_binary(host) and host != "" ->
          []

        _ ->
          [source_url: "must be an HTTP or HTTPS URL"]
      end
    end)
  end

  def value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  def editable(council) do
    %{
      version: council.version,
      lists:
        Enum.map(council.lists, fn l ->
          %{
            id: l.id,
            people_list_id: l.people_list_id,
            list_owner_id: l.list_owner_id,
            list_version: l.list_version,
            public: l.public,
            available: l.available,
            name: l.name,
            hall_id: l.hall_id,
            fallback: l.fallback,
            members: Enum.map(l.members, &Map.take(&1, [:author_id, :reason, :source_url]))
          }
        end)
    }
  end

  def add_member(%User{} = user, author_id, list_id \\ nil) do
    {:ok, council} = ensure(user.author_id)
    list = Enum.find(council.lists, fn l -> if list_id, do: l.id == list_id, else: l.fallback end)

    if list do
      attrs = editable(council)

      lists =
        Enum.map(attrs.lists, fn l ->
          if l.id == list.id and not Enum.any?(l.members, &(&1.author_id == author_id)),
            do: %{l | members: l.members ++ [%{author_id: author_id}]},
            else: l
        end)

      save(user, %{attrs | lists: lists})
    else
      {:error, :invalid_list}
    end
  end

  def settings(%User{} = user, attrs) do
    {:ok, council} = ensure(user.author_id)

    if Permissions.blocked?(user),
      do: {:error, :forbidden},
      else:
        council
        |> Ecto.Changeset.cast(attrs, [:digest])
        |> Ecto.Changeset.validate_inclusion(:digest, ["off", "daily", "weekly"])
        |> Repo.update()
  end

  # Council assignments are private, even when their selected lists are public.
  def public(_author_id), do: nil

  def delegate_ids(author_id) do
    Repo.all(
      from m in PeopleListMember,
        join: p in PeopleList,
        on: p.id == m.people_list_id,
        join: l in List,
        on: l.people_list_id == p.id,
        join: c in Council,
        on: c.id == l.council_id,
        where: c.author_id == ^author_id and m.author_id != ^author_id,
        where: p.public or p.author_id == ^author_id,
        select: m.author_id,
        distinct: true
    )
  end

  def followers(author_id) do
    Repo.all(
      from m in PeopleListMember,
        join: p in PeopleList,
        on: p.id == m.people_list_id,
        join: l in List,
        on: l.people_list_id == p.id,
        join: c in Council,
        on: c.id == l.council_id,
        where: m.author_id == ^author_id and c.author_id != ^author_id,
        where: p.public or p.author_id == c.author_id,
        select: c.author_id,
        distinct: true
    )
  end

  def sync_legacy(author_id) do
    ids = delegate_ids(author_id)

    Repo.delete_all(
      from d in YouCongress.Delegations.Delegation,
        where: d.deleguee_id == ^author_id and d.delegate_id not in ^ids
    )

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all(
      YouCongress.Delegations.Delegation,
      Enum.map(
        ids,
        &%{deleguee_id: author_id, delegate_id: &1, inserted_at: now, updated_at: now}
      ),
      on_conflict: :nothing
    )
  end

  def positions(ids, statement_id) do
    votes =
      Repo.all(
        from v in Vote,
          left_join: relation in OpinionStatement,
          on: relation.opinion_id == v.opinion_id and relation.statement_id == v.statement_id,
          where: v.author_id in ^ids and v.statement_id == ^statement_id and v.direct,
          preload: [:author, :opinion],
          select: {v, relation.verification_status}
      )

    Map.new(votes, fn {vote, relevance_status} ->
      {vote.author_id, position(vote, relevance_status)}
    end)
  end

  defp position(vote, relevance_status) do
    opinion = vote.opinion

    inferred = inferred?(vote)
    status = position_status(vote, inferred, relevance_status)

    eligible = status in ["self_cast", "verified", "endorsed", "ai_verified"]

    %{
      author_id: vote.author_id,
      name: vote.author.name || "Participant",
      answer: if(eligible, do: vote.answer),
      recorded_answer: vote.answer,
      status: status,
      origin: if(inferred, do: "inferred", else: "self_cast"),
      opinion_id: vote.opinion_id,
      source_url: opinion && opinion.source_url,
      source_text: opinion && opinion.source_text
    }
  end

  def inferred?(%{origin: "self_cast"}), do: false
  def inferred?(%{origin: "inferred"}), do: true
  def inferred?(%{opinion: opinion}), do: YouCongress.Opinions.Opinion.quote?(opinion)

  defp position_status(vote, true, relevance_status) do
    opinion = vote.opinion

    YouCongress.VerificationStatus.aggregate(
      opinion && opinion.verification_status,
      relevance_status,
      vote.verification_status
    )
    |> to_string()
  end

  defp position_status(%{twin: true}, false, _), do: "unverified"
  defp position_status(_, false, _), do: "self_cast"

  def refresh_for_halls(statement_id, hall_ids) do
    Repo.all(
      from c in Council,
        join: l in List,
        on: l.council_id == c.id,
        where: l.hall_id in ^hall_ids,
        select: c.author_id,
        distinct: true
    )
    |> Enum.each(fn author_id ->
      %{author_id: author_id, statement_id: statement_id}
      |> YouCongress.Workers.RefreshAuthorStatementDelegatedVotesWorker.new()
      |> Oban.insert()
    end)
  end

  def explain(author_or_council, statement_id, lists \\ nil)

  def explain(%Council{} = council, statement_id, lists) do
    author_id = council.author_id
    lists = lists || council.lists
    ids = lists |> Enum.flat_map(&Enum.map(&1.members, fn m -> m.author_id end)) |> Enum.uniq()

    hall_ids =
      Repo.all(
        from hs in YouCongress.HallsStatements.HallStatement,
          where: hs.statement_id == ^statement_id,
          select: hs.hall_id
      )

    result = Evaluator.evaluate(lists, positions(ids, statement_id), hall_ids)
    direct = Repo.get_by(Vote, author_id: author_id, statement_id: statement_id, direct: true)
    direct = if direct && direct.origin != "inferred", do: direct

    Map.merge(result, %{
      version: council.version,
      direct: direct && direct.answer,
      effective: if(direct, do: direct.answer, else: result.answer)
    })
  end

  def explain(author_id, statement_id, lists) do
    {:ok, council} = ensure(author_id)
    explain(council, statement_id, lists)
  end
end
