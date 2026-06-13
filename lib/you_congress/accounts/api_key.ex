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
    field :token, :string, virtual: true, redact: true
    field :token_hash, :binary, redact: true
    field :token_prefix, :string
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
    |> put_token_hash()
    |> unique_constraint(:token_hash)
  end

  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token)
  end

  defp put_token_hash(changeset) do
    case get_change(changeset, :token) do
      token when is_binary(token) ->
        changeset
        |> put_change(:token_hash, hash_token(token))
        |> put_change(:token_prefix, String.slice(token, 0, 8))

      _ ->
        changeset
    end
  end
end
