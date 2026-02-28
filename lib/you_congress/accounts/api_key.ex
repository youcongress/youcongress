defmodule YouCongress.Accounts.ApiKey do
  @moduledoc """
  API keys owned by individual users.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Accounts.User

  @scopes [:read, :write]

  schema "api_keys" do
    field :name, :string
    field :token, :string
    field :scope, Ecto.Enum, values: @scopes, default: :read

    belongs_to :user, User

    timestamps()
  end

  @doc """
  Changeset used when creating API keys through the UI.
  """
  def creation_changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :scope, :token])
    |> validate_required([:name, :scope, :token])
    |> validate_length(:name, max: 80)
    |> unique_constraint(:token)
  end
end
