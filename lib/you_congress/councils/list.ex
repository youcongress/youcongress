defmodule YouCongress.Councils.List do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "council_lists" do
    field :council_id, :id
    field :hall_id, :id
    field :name, :string, virtual: true
    field :members, {:array, :map}, virtual: true, default: []
    field :available, :boolean, virtual: true, default: true
    field :list_owner_id, :integer, virtual: true
    field :list_version, :integer, virtual: true
    field :public, :boolean, virtual: true, default: false
    belongs_to :people_list, YouCongress.Councils.PeopleList
    field :position, :integer
    field :fallback, :boolean, default: false
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:council_id, :hall_id, :people_list_id, :position, :fallback])
    |> validate_required([:council_id, :position])
  end
end
