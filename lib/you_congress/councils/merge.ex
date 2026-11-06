defmodule YouCongress.Councils.Merge do
  @moduledoc "Preserves Trust Network records when duplicate profiles are merged."
  import Ecto.Query
  alias YouCongress.{Repo, Councils}
  alias YouCongress.Councils.{Council, List, Member}
  alias YouCongress.TrustNetwork.{Membership, Recommendation, Notification, Request}

  def merge(duplicate_id, survivor_id) do
    merge_owned_councils(duplicate_id, survivor_id)
    move_unique(Member, :author_id, duplicate_id, survivor_id, [:list_id])
    move_unique(Membership, :author_id, duplicate_id, survivor_id, [:hall_id])
    move_unique(Recommendation, :author_id, duplicate_id, survivor_id, [:nominee_id, :scope])
    move_unique(Recommendation, :nominee_id, duplicate_id, survivor_id, [:author_id, :scope])
    move_unique(Notification, :author_id, duplicate_id, survivor_id, [:key])

    Repo.update_all(from(r in Request, where: r.author_id == ^duplicate_id),
      set: [author_id: survivor_id]
    )

    own_lists =
      Repo.all(
        from l in List,
          join: c in Council,
          on: c.id == l.council_id,
          where: c.author_id == ^survivor_id,
          select: l.id
      )

    Repo.delete_all(
      from m in Member, where: m.list_id in ^own_lists and m.author_id == ^survivor_id
    )

    if Councils.get(survivor_id), do: Councils.sync_legacy(survivor_id)
    :ok
  end

  defp merge_owned_councils(duplicate_id, survivor_id) do
    case {Councils.get(duplicate_id), Councils.get(survivor_id)} do
      {nil, _} ->
        :ok

      {duplicate, nil} ->
        duplicate
        |> Ecto.Changeset.change(author_id: survivor_id, version: duplicate.version + 1)
        |> Repo.update!()

      {duplicate, survivor} ->
        last = Enum.find(survivor.lists, & &1.fallback)
        next = length(survivor.lists) - 1

        duplicate.lists
        |> Enum.reject(& &1.fallback)
        |> Enum.with_index(next)
        |> Enum.each(fn {list, position} ->
          list
          |> Ecto.Changeset.change(council_id: survivor.id, position: position)
          |> Repo.update!()
        end)

        duplicate_last = Enum.find(duplicate.lists, & &1.fallback)
        move_unique(Member, :list_id, duplicate_last.id, last.id, [:author_id])

        last
        |> Ecto.Changeset.change(position: next + length(duplicate.lists) - 1)
        |> Repo.update!()

        survivor |> Ecto.Changeset.change(version: survivor.version + 1) |> Repo.update!()
        Repo.delete!(duplicate)
    end
  end

  defp move_unique(schema, key, duplicate, survivor, unique_keys) do
    Repo.all(from row in schema, where: field(row, ^key) == ^duplicate)
    |> Enum.each(fn row ->
      filters = [{key, survivor} | Enum.map(unique_keys, &{&1, Map.fetch!(row, &1)})]

      if Repo.get_by(schema, filters),
        do: Repo.delete!(row),
        else: row |> Ecto.Changeset.change(%{key => survivor}) |> Repo.update!()
    end)
  end
end
