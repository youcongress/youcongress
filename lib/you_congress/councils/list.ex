defmodule YouCongress.Councils.List do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "council_lists" do
    field :council_id, :id
    field :hall_id, :id
    field :name, :string
    field :position, :integer
    field :fallback, :boolean, default: false
    has_many :members, YouCongress.Councils.Member, foreign_key: :list_id
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:council_id, :hall_id, :name, :position, :fallback])
    |> validate_required([:council_id, :name, :position])
  end
end
