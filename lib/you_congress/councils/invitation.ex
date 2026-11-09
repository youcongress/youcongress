defmodule YouCongress.Councils.Invitation do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "council_invitations" do
    field :user_id, :id
    field :email, :string
    field :note, :string
    field :status, :string, default: "queued"
    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:user_id, :email, :note, :status])
    |> validate_required([:user_id, :email])
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/)
    |> validate_length(:note, max: 2_000)
    |> unique_constraint([:user_id, :email])
  end
end
