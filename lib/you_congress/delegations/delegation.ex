defmodule YouCongress.Delegations.Delegation do
  @moduledoc """
  The Delegation schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "delegations" do
    field :deleguee_id, :id
    field :delegate_id, :id

    timestamps()
  end

  @doc false
  def changeset(delegation, attrs) do
    delegation
    |> cast(attrs, [:deleguee_id, :delegate_id])
    |> validate_required([:deleguee_id, :delegate_id])
    |> unique_constraint(:deleguee_id, name: :index_delegations_on_deleguee_id_and_delegate_id)
    |> unique_constraint(:delegate_id, name: :index_delegations_on_deleguee_id_and_delegate_id)
  end
end
