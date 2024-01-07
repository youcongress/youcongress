defmodule YouCongress.Invitations.Invitation do
  @moduledoc """
  The Invitations context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "invitations" do
    field :twitter_username, :string
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:twitter_username])
    |> validate_required([:twitter_username])
  end
end
