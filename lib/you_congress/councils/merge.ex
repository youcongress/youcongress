defmodule YouCongress.Councils.Merge do
  @moduledoc "Preserves Trust Network records when duplicate profiles are merged."
  import Ecto.Query
  alias YouCongress.{Repo, Councils}
  alias YouCongress.Councils.{PeopleListMember, PeopleList}
  alias YouCongress.TrustNetwork.{Membership, Recommendation, Notification, Request}

  def merge(duplicate_id, survivor_id) do
    merge_owned_lists(duplicate_id, survivor_id)
    merge_owned_councils(duplicate_id, survivor_id)
    move_unique(PeopleListMember, :author_id, duplicate_id, survivor_id, [:people_list_id])
    move_unique(Membership, :author_id, duplicate_id, survivor_id, [:hall_id])
    move_unique(Recommendation, :author_id, duplicate_id, survivor_id, [:nominee_id, :scope])
    move_unique(Recommendation, :nominee_id, duplicate_id, survivor_id, [:author_id, :scope])
    move_unique(Notification, :author_id, duplicate_id, survivor_id, [:key])

    Repo.update_all(from(r in Request, where: r.author_id == ^duplicate_id),
      set: [author_id: survivor_id]
    )

    if Councils.get(survivor_id), do: Councils.sync_legacy(survivor_id)
    :ok
  end

  defp merge_owned_lists(duplicate_id, survivor_id) do
    Repo.all(from p in PeopleList, where: p.author_id == ^duplicate_id)
    |> Enum.each(fn list ->
      slug = YouCongress.PeopleLists.suggest_slug(survivor_id, list.slug)
      list |> Ecto.Changeset.change(author_id: survivor_id, slug: slug) |> Repo.update!()

      Repo.insert_all(
        "people_list_slugs",
        [%{author_id: survivor_id, people_list_id: list.id, slug: slug}],
        on_conflict: :nothing
      )
    end)
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
        |> Enum.with_index(next)
        |> Enum.each(fn {list, position} ->
          list
          |> Ecto.Changeset.change(council_id: survivor.id, position: position, fallback: false)
          |> Repo.update!()
        end)

        last
        |> Ecto.Changeset.change(position: next + length(duplicate.lists))
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
