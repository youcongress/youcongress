defmodule YouCongressWeb.MCPServer.AuthorsUpdate do
  @moduledoc """
  Update existing authors through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and own a role
  that passes `YouCongress.Accounts.Permissions.can_edit_author?/1`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias Ecto.NoResultsError
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Authors
  alias YouCongress.Authors.Author

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to edit this author."
  @not_found_message "Author not found."
  @missing_fields_message "Provide at least one field to update: name, one_line_bio, wikipedia_url, twitter_username, country."

  @author_fields [
    :name,
    :one_line_bio,
    :wikipedia_url,
    :twitter_username,
    :country
  ]

  schema do
    field :author_id, :integer, required: true
    field :name, :string
    field :one_line_bio, :string
    field :wikipedia_url, :string
    field :twitter_username, :string
    field :country, :string
  end

  @impl true
  def execute(%{author_id: author_id} = params, frame) do
    attrs = attrs_from_params(params)

    with :ok <- ensure_attrs_present(attrs),
         {:ok, user} <- authenticate_user(frame),
         {:ok, author} <- fetch_author(author_id),
         :ok <- ensure_permission(user),
         {:ok, updated_author} <- normalize_update_result(Authors.update_author(author, attrs)) do
      {:reply, Response.json(Response.tool(), %{author: take_fields(updated_author)}), frame}
    else
      {:error, :no_fields_to_update} ->
        {:reply, Response.error(Response.tool(), @missing_fields_message), frame}

      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not edit author: #{format_changeset_errors(changeset)}"
         ), frame}

      {:error, reason} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not edit author: #{format_unexpected_error(reason)}"
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

  defp ensure_attrs_present(%{} = attrs) when map_size(attrs) > 0, do: :ok
  defp ensure_attrs_present(_), do: {:error, :no_fields_to_update}

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp fetch_author(author_id) do
    {:ok, Authors.get_author!(author_id)}
  rescue
    NoResultsError -> {:error, :not_found}
  end

  defp ensure_permission(user) do
    if Permissions.can_edit_author?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp normalize_update_result({:ok, %Author{} = author}), do: {:ok, author}

  defp normalize_update_result({:ok, %{update_author: %Author{} = author}}) do
    {:ok, author}
  end

  defp normalize_update_result({:error, :update_author, %Changeset{} = changeset, _changes}) do
    {:error, changeset}
  end

  defp normalize_update_result({:error, _step, %Changeset{} = changeset, _changes}) do
    {:error, changeset}
  end

  defp normalize_update_result({:error, :update_author, reason, _changes}) do
    {:error, reason}
  end

  defp normalize_update_result(result), do: result

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

  defp format_unexpected_error(reason) when is_binary(reason), do: reason
  defp format_unexpected_error(reason), do: inspect(reason)
end
