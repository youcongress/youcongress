defmodule YouCongress.TrustNetwork.Snapshot do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "trust_snapshots" do
    field :title, :string
    field :scope, :string
    field :filters, :map
    field :result, :map
    field :user_id, :id
    timestamps(updated_at: false)
  end

  def changeset(record, attrs),
    do:
      record
      |> cast(attrs, [:title, :scope, :filters, :result, :user_id])
      |> validate_required([:title, :scope, :result])
end
