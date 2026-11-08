defmodule YouCongress.PeopleLists do
  @moduledoc "Named public lists, independent of private Council membership and voting."
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

  defp preload(nil), do: nil
  defp preload(list), do: Repo.preload(list, :members)

  def for_author(author_id),
    do:
      Repo.all(
        from l in PeopleList,
          where: l.author_id == ^author_id,
          order_by: [desc: l.updated_at, desc: l.id],
          preload: [:members]
      )

  def create(%User{} = user, attrs) do
    if Permissions.blocked?(user), do: {:error, :forbidden}, else: persist(user, nil, attrs)
  end

  def create(_, _), do: {:error, :forbidden}

  def update(%User{} = user, id, attrs) do
    if Permissions.blocked?(user), do: {:error, :forbidden}, else: persist(user, id, attrs)
  end

  def update(_, _, _), do: {:error, :forbidden}

  def delete(%User{} = user, id) do
    case if(Permissions.blocked?(user), do: nil, else: get(id)) do
      %PeopleList{author_id: owner} = list when owner == user.author_id -> Repo.delete(list)
      _ -> {:error, :forbidden}
    end
  end

  def delete(_, _), do: {:error, :forbidden}

  defp persist(user, id, attrs) do
    Repo.transaction(fn ->
      list = owned_list!(user, id)
      if id && Councils.value(attrs, :version) != list.version, do: Repo.rollback(:stale)
      members = Councils.value(attrs, :members) || []
      validate_members!(members)

      changeset =
        PeopleList.changeset(list, %{
          author_id: user.author_id,
          name: Councils.value(attrs, :name),
          version: if(id, do: list.version + 1, else: 1)
        })

      list =
        case Repo.insert_or_update(changeset) do
          {:ok, list} -> list
          {:error, error} -> Repo.rollback(error)
        end

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

      get(list.id)
    end)
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
