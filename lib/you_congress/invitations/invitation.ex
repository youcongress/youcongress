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
    |> cast(attrs, [:twitter_username, :user_id])
    |> validate_required([:twitter_username])
    |> remove_at_from_twitter_username()
    |> unique_constraint(:twitter_username)
  end

  defp remove_at_from_twitter_username(changeset) do
    original = get_field(changeset, :twitter_username)

    with true <- is_binary(original),
         replaced <- String.replace(original, "@", ""),
         true <- original != replaced do
      put_change(changeset, :twitter_username, replaced)
    else
      _ ->
        changeset
    end
  end
end
