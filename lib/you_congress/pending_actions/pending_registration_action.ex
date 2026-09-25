defmodule YouCongress.PendingActions.PendingRegistrationAction do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Accounts.User

  schema "pending_registration_actions" do
    field :payload, :map
    field :expires_at, :utc_datetime
    belongs_to :user, User

    timestamps()
  end

  def changeset(pending_action, attrs) do
    pending_action
    |> cast(attrs, [:user_id, :payload, :expires_at])
    |> validate_required([:user_id, :payload, :expires_at])
    |> unique_constraint(:user_id)
  end
end
