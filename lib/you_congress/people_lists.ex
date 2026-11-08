defmodule YouCongress.PeopleLists do
  @moduledoc "Named public lists with optional private links that synchronize Council membership."
  import Ecto.Query
  alias YouCongress.{Repo, Councils, TrustRankings}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Councils.{PeopleList, PeopleListMember}
  alias YouCongress.Authors.Author

  def get(raw_id) do
    case TrustRankings.parse_id(raw_id) do
      nil -> nil
      id -> Repo.get(PeopleList, id) |> preload()
    end
  end

  def get_by_slug(author_id, slug) when is_integer(author_id) and is_binary(slug) do
    Repo.one(
      from l in PeopleList,
        join: s in "people_list_slugs",
        on: s.people_list_id == l.id,
        where: s.author_id == ^author_id and s.slug == ^slug
    )
    |> preload()
  end

  def get_by_slug(_, _), do: nil

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

  defp preload(nil), do: nil
  defp preload(list), do: Repo.preload(list, :members)

  def has_public_lists?(author_id),
    do: Repo.exists?(from l in PeopleList, where: l.author_id == ^author_id)

  def for_author(author_id),
    do:
      Repo.all(
        from l in PeopleList,
          where: l.author_id == ^author_id,
          order_by: [desc: l.updated_at, desc: l.id],
          preload: [:members]
      )

  # This association is private account data, never part of the public list schema.
  def linked_list(user, council_list_id \\ nil)

  def linked_list(%User{author_id: author_id}, council_list_id) do
    council = Councils.get(author_id)
    target = council_list_id || (council && Enum.find(council.lists, & &1.fallback).id)

    Repo.one(
      from l in PeopleList,
        join: link in "council_public_list_links",
        on: link.people_list_id == l.id,
        where:
          link.author_id == ^author_id and link.council_list_id == ^(target || 0) and
            l.author_id == ^author_id
    )
    |> preload()
  end

  def linked_list(_, _), do: nil

  def linked_council_list_id(%User{author_id: author_id}, people_list_id) do
    Repo.one(
      from link in "council_public_list_links",
        where: link.author_id == ^author_id and link.people_list_id == ^people_list_id,
        select: link.council_list_id
    )
  end

  def create(%User{} = user, attrs) do
    if Permissions.blocked?(user), do: {:error, :forbidden}, else: persist(user, nil, attrs)
  end

  def create(_, _), do: {:error, :forbidden}

  def update(%User{} = user, id, attrs) do
    if Permissions.blocked?(user), do: {:error, :forbidden}, else: persist(user, id, attrs)
  end

  def update(_, _, _), do: {:error, :forbidden}

  def delete(%User{} = user, id) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      Repo.transaction(fn ->
        lock_owner!(user.author_id)
        if is_nil(TrustRankings.parse_id(id)), do: Repo.rollback(:forbidden)
        user |> owned_list!(id) |> Repo.delete!()
      end)
    end
  end

  def delete(_, _), do: {:error, :forbidden}

  defp persist(user, id, attrs) do
    Repo.transaction(fn ->
      lock_owner!(user.author_id)
      list = owned_list!(user, id)
      if id && Councils.value(attrs, :version) != list.version, do: Repo.rollback(:stale)
      members = Councils.value(attrs, :members) || []
      validate_members!(members)

      changeset =
        PeopleList.changeset(list, %{
          author_id: user.author_id,
          name: Councils.value(attrs, :name),
          slug: list_slug(user, list, attrs),
          version: if(id, do: list.version + 1, else: 1)
        })

      list =
        case Repo.insert_or_update(changeset) do
          {:ok, list} -> list
          {:error, error} -> Repo.rollback(error)
        end

      reserve_slug!(list, changeset)

      Repo.delete_all(from m in PeopleListMember, where: m.people_list_id == ^list.id)

      Enum.with_index(members)
      |> Enum.each(fn {member, position} ->
        changeset =
          PeopleListMember.changeset(%PeopleListMember{}, %{
            people_list_id: list.id,
            author_id: Councils.value(member, :author_id),
            reason: Councils.value(member, :reason),
            position: position
          })

        case Repo.insert(changeset) do
          {:ok, _} -> :ok
          {:error, error} -> Repo.rollback(error)
        end
      end)

      save_council_link(
        user,
        list,
        Councils.value(attrs, :link_council),
        Councils.value(attrs, :council_list_id)
      )

      list = get(list.id)
      linked = linked_council_list_id(user, list.id)

      changed =
        if linked,
          do:
            Councils.sync_members_from_list(
              user.author_id,
              Enum.map(list.members, & &1.author_id),
              linked
            ),
          else: false

      {list, changed}
    end)
    |> finish_save(user)
  end

  defp finish_save({:ok, {list, changed}}, user) do
    if changed, do: YouCongress.DelegationVotes.update_author_delegated_votes(user.author_id)
    {:ok, list}
  end

  defp finish_save(error, _user), do: error

  defp lock_owner!(author_id),
    do: Repo.one!(from a in Author, where: a.id == ^author_id, lock: "FOR UPDATE")

  @doc false
  def sync_members_from_council(council) do
    unless Repo.in_transaction?(),
      do: raise(ArgumentError, "membership sync requires a transaction")

    Enum.each(council.lists, fn topic ->
      case linked_list(%User{author_id: council.author_id}, topic.id) do
        nil -> :ok
        list -> sync_public_members(list, Enum.map(topic.members, & &1.author_id))
      end
    end)
  end

  defp sync_public_members(list, ids) do
    existing = Map.new(list.members, &{&1.author_id, &1})

    if MapSet.new(Map.keys(existing)) != MapSet.new(ids) do
      Repo.delete_all(
        from m in PeopleListMember,
          where: m.people_list_id == ^list.id and m.author_id not in ^ids
      )

      Enum.with_index(ids)
      |> Enum.each(fn {id, position} ->
        member = existing[id] || %PeopleListMember{}

        member
        |> PeopleListMember.changeset(%{
          people_list_id: list.id,
          author_id: id,
          position: position
        })
        |> Repo.insert_or_update!()
      end)

      list |> Ecto.Changeset.change(version: list.version + 1) |> Repo.update!()
    end

    :ok
  end

  defp save_council_link(user, list, value, raw_id) when value in [true, "true"] do
    {:ok, council} = Councils.ensure(user.author_id)

    target =
      if raw_id,
        do: Enum.find(council.lists, &(&1.id == TrustRankings.parse_id(raw_id))),
        else: Enum.find(council.lists, & &1.fallback)

    if is_nil(target), do: Repo.rollback(:invalid_list)

    Repo.delete_all(
      from link in "council_public_list_links",
        where: link.author_id == ^user.author_id and link.people_list_id == ^list.id
    )

    Repo.insert_all(
      "council_public_list_links",
      [%{author_id: user.author_id, people_list_id: list.id, council_list_id: target.id}],
      on_conflict: {:replace, [:people_list_id]},
      conflict_target: [:council_list_id]
    )
  end

  defp save_council_link(user, list, value, _id) when value in [false, "false"] do
    Repo.delete_all(
      from link in "council_public_list_links",
        where: link.author_id == ^user.author_id and link.people_list_id == ^list.id
    )
  end

  defp save_council_link(_user, _list, _value, _id), do: :ok

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
