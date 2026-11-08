defmodule YouCongress.Councils.PeopleListMember do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "people_list_members" do
    field :people_list_id, :id
    field :author_id, :id
    field :reason, :string
    field :position, :integer
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:people_list_id, :author_id, :reason, :position])
    |> validate_required([:people_list_id, :author_id, :position])
    |> validate_length(:reason, max: 5_000)
  end
end
