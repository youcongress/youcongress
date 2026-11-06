defmodule YouCongress.Councils do
  @moduledoc "Saved ordered councils, including repeatable topic and General lists."
  import Ecto.Query
  alias YouCongress.{Repo, Halls, Authors}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Councils.{Council, List, Member, Evaluator}
  alias YouCongress.Votes.Vote

  def get(author_id), do: Repo.get_by(Council, author_id: author_id) |> preload()
  defp preload(nil), do: nil
  defp preload(council), do: Repo.preload(council, lists: :members)

  def ensure(author_id) do
    Repo.transaction(fn ->
      Repo.one!(from a in Authors.Author, where: a.id == ^author_id, lock: "FOR UPDATE")

      case get(author_id) do
        nil ->
          council = Repo.insert!(Council.changeset(%Council{}, %{author_id: author_id}))

          Enum.each(Enum.with_index(default_lists()), fn {attrs, index} ->
            Repo.insert!(
              List.changeset(
                %List{},
                Map.merge(attrs, %{council_id: council.id, position: index})
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

          Enum.each(
            legacy,
            &Repo.insert!(Member.changeset(%Member{}, %{list_id: fallback.id, author_id: &1}))
          )

          get(author_id)

        council ->
          council
      end
    end)
  end

  def default_lists do
    Enum.map(
      [{"ai-governance", "AI governance"}, {"impact-on-labor", "Impact on Jobs"}],
      fn {slug, name} ->
        {:ok, hall} = Halls.get_or_create_by_name(slug)
        %{hall_id: hall.id, name: name, fallback: false}
      end
    ) ++ [%{hall_id: nil, name: "General", fallback: true}]
  end

  def save(%User{} = user, attrs) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      {:ok, _} = ensure(user.author_id)

      result =
        Repo.transaction(fn ->
          council =
            Repo.one!(
              from c in Council, where: c.author_id == ^user.author_id, lock: "FOR UPDATE"
            )
            |> preload()

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
          get(user.author_id)
        end)

      case result do
        {:ok, council} ->
          YouCongress.DelegationVotes.update_author_delegated_votes(user.author_id)
          YouCongress.Track.event("Council saved", user)
          {:ok, council}

        error ->
          error
      end
    end
  end

  def save(_, _), do: {:error, :forbidden}

  defp validate_lists!(council, lists) do
    unless is_list(lists) and Enum.all?(lists, &is_map/1), do: Repo.rollback(:invalid_lists)
    fallback = Enum.find(council.lists, & &1.fallback)
    ids = Enum.map(lists, &value(&1, :id)) |> Enum.reject(&is_nil/1)
    owned = Enum.map(council.lists, & &1.id)

    valid =
      lists != [] and length(ids) == length(Enum.uniq(ids)) and
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
    name = list_name!(attrs, hall)

    list =
      existing
      |> List.changeset(%{council_id: council.id, hall_id: hall_id, name: name, position: index})
      |> Repo.insert_or_update!()

    save_members!(council.author_id, list, value(attrs, :members) || [])
  end

  defp list_name!(attrs, hall) do
    raw_name = value(attrs, :name) || default_name(hall)
    unless is_binary(raw_name), do: Repo.rollback(:invalid_name)
    name = String.trim(raw_name)
    if name == "" or String.length(name) > 120, do: Repo.rollback(:invalid_name)
    name
  end

  defp default_name(nil), do: "General"
  defp default_name(hall), do: hall.name

  defp save_members!(owner_id, list, members) do
    unless is_list(members) and Enum.all?(members, &is_map/1), do: Repo.rollback(:invalid_members)
    member_ids = Enum.map(members, &value(&1, :author_id))

    if owner_id in member_ids or length(member_ids) != length(Enum.uniq(member_ids)),
      do: Repo.rollback(:invalid_members)

    found = Repo.aggregate(from(a in Authors.Author, where: a.id in ^member_ids), :count)
    if found != length(member_ids), do: Repo.rollback(:invalid_members)

    Repo.delete_all(
      from m in Member, where: m.list_id == ^list.id and m.author_id not in ^member_ids
    )

    Enum.each(members, fn m ->
      member = Repo.get_by(Member, list_id: list.id, author_id: value(m, :author_id)) || %Member{}

      changeset =
        Member.changeset(member, %{
          list_id: list.id,
          author_id: value(m, :author_id),
          reason: value(m, :reason),
          source_url: value(m, :source_url)
        })
        |> Ecto.Changeset.validate_length(:reason, max: 5_000)
        |> validate_url()

      case Repo.insert_or_update(changeset) do
        {:ok, _} -> :ok
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

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
        |> Ecto.Changeset.cast(attrs, [:published, :digest])
        |> Ecto.Changeset.validate_inclusion(:digest, ["off", "daily", "weekly"])
        |> Repo.update()
  end

  def public(author_id) do
    case get(author_id) do
      %Council{published: true} = council -> council
      _ -> nil
    end
  end

  def delegate_ids(author_id) do
    Repo.all(
      from m in Member,
        join: l in List,
        on: l.id == m.list_id,
        join: c in Council,
        on: c.id == l.council_id,
        where: c.author_id == ^author_id,
        select: m.author_id,
        distinct: true
    )
  end

  def followers(author_id) do
    Repo.all(
      from m in Member,
        join: l in List,
        on: l.id == m.list_id,
        join: c in Council,
        on: c.id == l.council_id,
        where: m.author_id == ^author_id,
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
          where: v.author_id in ^ids and v.statement_id == ^statement_id and v.direct,
          preload: [:author, :opinion]
      )

    Map.new(votes, fn v -> {v.author_id, position(v)} end)
  end

  def position(vote) do
    opinion = vote.opinion

    inferred = inferred?(vote)
    status = position_status(vote, inferred)

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

  defp position_status(vote, true) do
    opinion = vote.opinion

    relation =
      if opinion,
        do:
          Repo.get_by(YouCongress.OpinionsStatements.OpinionStatement,
            opinion_id: opinion.id,
            statement_id: vote.statement_id
          )

    YouCongress.VerificationStatus.aggregate(
      opinion && opinion.verification_status,
      relation && relation.verification_status,
      vote.verification_status
    )
    |> to_string()
  end

  defp position_status(%{twin: true}, false), do: "unverified"
  defp position_status(_, false), do: "self_cast"

  def explain(author_id, statement_id, lists \\ nil) do
    {:ok, council} = ensure(author_id)
    lists = lists || council.lists
    ids = lists |> Enum.flat_map(&Enum.map(&1.members, fn m -> m.author_id end)) |> Enum.uniq()
    result = Evaluator.evaluate(lists, positions(ids, statement_id))
    direct = Repo.get_by(Vote, author_id: author_id, statement_id: statement_id, direct: true)
    direct = if direct && direct.origin != "inferred", do: direct

    Map.merge(result, %{
      version: council.version,
      direct: direct && direct.answer,
      effective: if(direct, do: direct.answer, else: result.answer)
    })
  end
end
