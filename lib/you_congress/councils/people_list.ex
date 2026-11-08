defmodule YouCongress.Councils.PeopleList do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "people_lists" do
    field :author_id, :id
    field :name, :string
    field :slug, :string
    field :version, :integer, default: 1

    has_many :members, YouCongress.Councils.PeopleListMember,
      preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:author_id, :name, :slug, :version])
    |> update_change(:name, &trim/1)
    |> update_change(:slug, &normalize_slug/1)
    |> validate_required([:author_id, :name, :slug])
    |> validate_length(:slug, max: 80)
    |> validate_format(:slug, ~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
      message: "use lowercase letters, numbers, and single hyphens between words"
    )
    |> unique_constraint(:slug, name: :people_lists_author_id_slug_index)
    |> validate_length(:name, max: 120)
  end

  defp trim(nil), do: nil
  defp trim(text), do: String.trim(text)
  defp normalize_slug(nil), do: nil
  defp normalize_slug(slug), do: slug |> String.trim() |> String.downcase()
end
