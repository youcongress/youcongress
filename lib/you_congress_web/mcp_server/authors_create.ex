defmodule YouCongressWeb.MCPServer.AuthorsCreate do
  @moduledoc """
  Create new authors through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and own a role
  that passes `YouCongress.Accounts.Permissions.can_create_authors?/1`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Authors

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to create authors."

  @author_fields [
    :name,
    :one_line_bio,
    :wikipedia_url,
    :twitter_username,
    :country
  ]

  schema do
    field :name, :string
    field :one_line_bio, :string
    field :wikipedia_url, :string
    field :twitter_username, :string
    field :country, :string
  end

  @impl true
  def execute(params, frame) do
    attrs =
      params
      |> attrs_from_params()
      |> Map.put(:twin_origin, false)

    with {:ok, user} <- authenticate_user(frame),
         :ok <- ensure_permission(user),
         {:ok, author} <- Authors.create_author(attrs) do
      {:reply, Response.json(Response.tool(), %{author: take_fields(author)}), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not create author: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp attrs_from_params(params) do
    params
    |> Map.take(@author_fields)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> rename_one_line_bio()
  end

  defp rename_one_line_bio(attrs) do
    case Map.pop(attrs, :one_line_bio) do
      {nil, attrs} -> attrs
      {one_line_bio, attrs} -> Map.put(attrs, :bio, one_line_bio)
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(user) do
    if Permissions.can_create_authors?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp take_fields(author) do
    %{
      author_id: author.id,
      name: author.name,
      one_line_bio: author.bio,
      wikipedia_url: author.wikipedia_url,
      twitter_username: author.twitter_username,
      country: author.country
    }
  end

  defp format_changeset_errors(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(&replace_error_vars/1)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message -> "#{field} #{message}" end)
    end)
    |> Enum.join("; ")
  end

  defp replace_error_vars({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
