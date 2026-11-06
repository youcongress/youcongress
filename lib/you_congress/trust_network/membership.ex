defmodule YouCongress.TrustNetwork.Membership do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "community_memberships" do
    field :author_id, :id
    field :hall_id, :id
    timestamps()
  end

  def changeset(record, attrs),
    do: record |> cast(attrs, [:author_id, :hall_id]) |> validate_required([:author_id, :hall_id])
end
