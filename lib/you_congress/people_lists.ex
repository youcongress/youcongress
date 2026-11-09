defmodule YouCongress.PeopleLists do
  @moduledoc "Owned private or public lists, referenced directly by private Council assignments."
  import Ecto.Query
  alias YouCongress.{Repo, Councils, TrustRankings}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Councils.{PeopleList, PeopleListMember, Council, List}
  alias YouCongress.Authors.Author

  def get(raw_id, user \\ nil) do
    case TrustRankings.parse_id(raw_id) do
      nil -> nil
      id -> Repo.get(PeopleList, id) |> visible(user) |> preload()
    end
  end

  def accessible?(nil, _), do: false
  def accessible?(%{public: true}, _), do: true
  def accessible?(%{author_id: id}, %User{author_id: id}), do: true
  def accessible?(_, _), do: false
  defp visible(list, user), do: if(accessible?(list, user), do: list)
  defp preload(nil), do: nil
  defp preload(list), do: Repo.preload(list, :members)

  def get_by_slug(author_id, slug, user \\ nil) do
    Repo.one(
      from l in PeopleList,
        join: s in "people_list_slugs",
        on: s.people_list_id == l.id,
        where: s.author_id == ^author_id and s.slug == ^slug
    )
    |> visible(user)
    |> preload()
  end

  def has_public_lists?(author_id),
    do: Repo.exists?(from l in PeopleList, where: l.author_id == ^author_id and l.public)

  def for_author(author_id, user \\ nil) do
    query =
      from l in PeopleList,
        where: l.author_id == ^author_id,
        order_by: [desc: l.updated_at, desc: l.id],
        preload: [:members]

    query = if user && user.author_id == author_id, do: query, else: where(query, [l], l.public)
    Repo.all(query)
  end

  def search_public(query, opts \\ []) do
    term = "%#{String.slice(String.trim(query), 0, 120)}%"
    owner = Keyword.get(opts, :author_id)
    viewer = Keyword.get(opts, :viewer_id, 0)

    from(l in PeopleList,
      join: a in Author,
      on: a.id == l.author_id,
      left_join: m in PeopleListMember,
      on: m.people_list_id == l.id,
      where: l.public or l.author_id == ^viewer,
      where: ilike(l.name, ^term) or ilike(a.name, ^term) or ilike(a.twitter_username, ^term),
      group_by: [l.id, a.name],
      order_by: [desc: l.updated_at, desc: l.id],
      limit: ^Keyword.get(opts, :limit, 30),
      select: %{
        id: l.id,
        name: l.name,
        public: l.public,
        author_id: l.author_id,
        author_name: a.name,
        count: count(m.id)
      }
    )
    |> then(fn q -> if owner, do: where(q, [l], l.author_id == ^owner), else: q end)
    |> Repo.all()
  end

  # Assignment information is only available for the Council owner.
  def linked_lists(%User{author_id: author_id} = user) do
    Repo.all(
      from l in List,
        join: c in Council,
        on: c.id == l.council_id,
        join: p in PeopleList,
        on: p.id == l.people_list_id,
        where: c.author_id == ^author_id,
        select: {l.id, p}
    )
    |> Enum.filter(fn {_, p} -> accessible?(p, user) end)
    |> Map.new()
  end

  def linked_lists(_), do: %{}

  def linked_list(user, council_list_id \\ nil)

  def linked_list(%User{} = user, council_list_id) do
    council = Councils.get(user.author_id)
    target = council_list_id || (council && Enum.find(council.lists, & &1.fallback).id)
    linked_lists(user)[target] |> preload()
  end

  def linked_list(_, _), do: nil

  def linked_council_list_id(%User{author_id: author_id}, people_list_id) do
    Repo.one(
      from l in List,
        join: c in Council,
        on: c.id == l.council_id,
        where: c.author_id == ^author_id and l.people_list_id == ^people_list_id,
        order_by: l.position,
        limit: 1,
        select: l.id
    )
  end

  def use_for_council(%User{} = user, source_id, target_id, version, copy?) do
    if Permissions.blocked?(user),
      do: {:error, :forbidden},
      else: assign_source(user, source_id, target_id, version, copy?)
  end

  defp assign_source(user, source_id, target_id, version, copy?) do
    result =
      Repo.transaction(fn ->
        lock_owner!(user.author_id)
        {:ok, _} = Councils.ensure(user.author_id)

        council =
          Repo.one!(from c in Council, where: c.author_id == ^user.author_id, lock: "FOR UPDATE")

        if council.version != version, do: Repo.rollback(:stale)
        target = Repo.get(List, TrustRankings.parse_id(target_id) || 0)
        unless target && target.council_id == council.id, do: Repo.rollback(:invalid_list)
        source = get(source_id, user) || Repo.rollback(:not_found)

        source =
          if copy?,
            do:
              write!(user, nil, %{
                name: String.slice(source.name, 0, 113) <> " (copy)",
                public: false,
                members:
                  Enum.map(source.members, &Map.take(&1, [:author_id, :reason, :source_url]))
              }),
            else: source

        target |> Ecto.Changeset.change(people_list_id: source.id) |> Repo.update!()
        council |> Ecto.Changeset.change(version: council.version + 1) |> Repo.update!()
      end)

    case result do
      {:ok, _} ->
        refresh_authors([user.author_id])
        {:ok, Councils.get(user.author_id)}

      error ->
        error
    end
  end

  def create(%User{} = user, attrs), do: persist(user, nil, attrs)
  def create(_, _), do: {:error, :forbidden}
  def update(%User{} = user, id, attrs), do: persist(user, id, attrs)
  def update(_, _, _), do: {:error, :forbidden}

  defp persist(user, id, attrs) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      result =
        Repo.transaction(fn ->
          lock_owner!(user.author_id)
          list = write!(user, id, attrs)
          attach_to_council!(user, list, attrs)

          list
        end)

      case result do
        {:ok, list} ->
          refresh_dependents([list.id])
          {:ok, list}

        error ->
          error
      end
    end
  end

  defp attach_to_council!(user, list, attrs) do
    if Councils.value(attrs, :link_council) in [true, "true"] do
      {:ok, council} = Councils.ensure(user.author_id)
      target_id = TrustRankings.parse_id(Councils.value(attrs, :council_list_id))
      target = Enum.find(council.lists, &target_list?(&1, target_id))
      if is_nil(target), do: Repo.rollback(:invalid_list)
      target |> Ecto.Changeset.change(people_list_id: list.id) |> Repo.update!()
      council |> Ecto.Changeset.change(version: council.version + 1) |> Repo.update!()
    end
  end

  defp target_list?(list, nil), do: list.fallback
  defp target_list?(list, id), do: list.id == id

  defp list_visibility(attrs, list) do
    if Map.has_key?(attrs, :public) || Map.has_key?(attrs, "public"),
      do: Councils.value(attrs, :public) in [true, "true"],
      else: list.public
  end

  # Called within the Council transaction as well as the ordinary list editor.
  def write!(%User{} = user, id, attrs) do
    unless Repo.in_transaction?(), do: raise(ArgumentError, "list write requires a transaction")
    if Permissions.blocked?(user), do: Repo.rollback(:forbidden)
    list = owned_list!(user, id)
    if id && Councils.value(attrs, :version) != list.version, do: Repo.rollback(:stale)

    members =
      Councils.value(attrs, :members) ||
        if(id, do: Enum.map(Repo.preload(list, :members).members, &Map.from_struct/1), else: [])

    validate_members!(members)

    changeset =
      PeopleList.changeset(list, %{
        author_id: user.author_id,
        name: Councils.value(attrs, :name) || list.name,
        slug: list_slug(user, list, attrs),
        public: list_visibility(attrs, list),
        version: if(id, do: list.version + 1, else: 1)
      })

    list =
      case Repo.insert_or_update(changeset) do
        {:ok, list} -> list
        {:error, error} -> Repo.rollback(error)
      end

    reserve_slug!(list, changeset)
    save_members!(list, members)
    touch_dependents!(list.id)
    preload(list)
  end

  defp save_members!(list, members) do
    ids = Enum.map(members, &Councils.value(&1, :author_id))

    Repo.delete_all(
      from m in PeopleListMember, where: m.people_list_id == ^list.id and m.author_id not in ^ids
    )

    existing_members =
      Repo.all(from m in PeopleListMember, where: m.people_list_id == ^list.id)
      |> Map.new(&{&1.author_id, &1})

    Enum.with_index(members)
    |> Enum.each(fn {m, position} ->
      existing = existing_members[Councils.value(m, :author_id)] || %PeopleListMember{}

      changeset =
        PeopleListMember.changeset(existing, %{
          people_list_id: list.id,
          author_id: Councils.value(m, :author_id),
          reason: Councils.value(m, :reason),
          source_url: Councils.value(m, :source_url),
          position: position
        })

      case Repo.insert_or_update(changeset) do
        {:ok, _} -> :ok
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def delete(%User{} = user, id) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      result =
        Repo.transaction(fn ->
          lock_owner!(user.author_id)
          list = owned_list!(user, TrustRankings.parse_id(id) || 0)
          authors = dependent_authors([list.id])
          touch_dependents!(list.id)
          {Repo.delete!(list), authors}
        end)

      case result do
        {:ok, {list, authors}} ->
          refresh_authors(authors)
          {:ok, list}

        error ->
          error
      end
    end
  end

  def delete(_, _), do: {:error, :forbidden}

  defp touch_dependents!(id) do
    ids = from l in List, where: l.people_list_id == ^id, select: l.council_id
    Repo.update_all(from(c in Council, where: c.id in subquery(ids)), inc: [version: 1])
  end

  def dependent_authors(ids) do
    Repo.all(
      from c in Council,
        join: l in List,
        on: l.council_id == c.id,
        where: l.people_list_id in ^ids,
        select: c.author_id,
        distinct: true
    )
  end

  def refresh_dependents(ids), do: refresh_authors(dependent_authors(ids))

  def refresh_authors(ids) do
    Enum.each(Enum.uniq(ids), fn id ->
      Councils.sync_legacy(id)
      YouCongress.DelegationVotes.update_author_delegated_votes(id)
    end)
  end

  defp lock_owner!(author_id),
    do: Repo.one!(from a in Author, where: a.id == ^author_id, lock: "FOR UPDATE")

  def slugify(name) do
    slug =
      name
      |> to_string()
      |> Slug.slugify()
      |> to_string()
      |> String.slice(0, 70)
      |> String.trim_trailing("-")

    if slug == "", do: "list", else: slug
  end

  def suggest_slug(author_id, name), do: available_slug(author_id, slugify(name), 1)

  defp available_slug(author_id, base, suffix) do
    slug = if suffix == 1, do: base, else: "#{base}-#{suffix}"

    if Repo.exists?(
         from s in "people_list_slugs", where: s.author_id == ^author_id and s.slug == ^slug
       ), do: available_slug(author_id, base, suffix + 1), else: slug
  end

  defp list_slug(user, list, attrs) do
    Councils.value(attrs, :slug) || list.slug ||
      suggest_slug(user.author_id, Councils.value(attrs, :name))
  end

  defp reserve_slug!(list, changeset) do
    Repo.insert_all(
      "people_list_slugs",
      [
        %{author_id: list.author_id, people_list_id: list.id, slug: list.slug}
      ],
      on_conflict: :nothing,
      conflict_target: [:author_id, :slug]
    )

    claimed_by =
      Repo.one(
        from s in "people_list_slugs",
          where: s.author_id == ^list.author_id and s.slug == ^list.slug,
          select: s.people_list_id
      )

    if claimed_by != list.id do
      changeset
      |> Ecto.Changeset.add_error(
        :slug,
        "is already used by another list or one of its old links"
      )
      |> Repo.rollback()
    end
  end

  defp owned_list!(_user, nil), do: %PeopleList{}

  defp owned_list!(user, id) do
    case Repo.one(
           from l in PeopleList,
             where: l.id == ^id and l.author_id == ^user.author_id,
             lock: "FOR UPDATE"
         ) do
      nil -> Repo.rollback(:forbidden)
      list -> list
    end
  end

  defp validate_members!(members) do
    unless is_list(members) && Enum.all?(members, &is_map/1), do: Repo.rollback(:invalid_members)
    ids = Enum.map(members, &Councils.value(&1, :author_id))

    unless length(ids) == length(Enum.uniq(ids)) && Enum.all?(ids, &is_integer/1),
      do: Repo.rollback(:invalid_members)

    if Repo.aggregate(from(a in Author, where: a.id in ^ids), :count) != length(ids),
      do: Repo.rollback(:invalid_members)
  end
end
