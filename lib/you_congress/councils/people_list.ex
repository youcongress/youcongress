defmodule YouCongress.Councils.PeopleList do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "people_lists" do
    field :author_id, :id
    field :name, :string
    field :version, :integer, default: 1

    has_many :members, YouCongress.Councils.PeopleListMember,
      preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:author_id, :name, :version])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:author_id, :name])
    |> validate_length(:name, max: 120)
  end
end
