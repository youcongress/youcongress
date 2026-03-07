defmodule YouCongressWeb.MCPServer.OpinionsDelete do
  @moduledoc """
  Delete an existing opinion through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and have
  permission to edit the target opinion.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.{Frame, Response}
  alias Ecto.Changeset
  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to delete this opinion."
  @not_found_message "Opinion not found."
  @delete_error_message "Could not delete opinion."

  schema do
    field :opinion_id, :integer, required: true
  end

  @impl true
  def execute(%{opinion_id: opinion_id}, frame) do
    with {:ok, user} <- authenticate_user(frame),
         opinion when not is_nil(opinion) <- Opinions.get_opinion(opinion_id),
         :ok <- ensure_permission(opinion, user),
         {:ok, _deleted_opinion} <- Opinions.delete_opinion(opinion) do
      data = %{deleted: true, deleted_opinion_id: opinion_id}
      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "#{@delete_error_message} #{format_changeset_errors(changeset)}"
         ), frame}

      {:error, _} ->
        {:reply, Response.error(Response.tool(), @delete_error_message), frame}
    end
  end

  defp authenticate_user(frame) do
    frame
    |> Frame.get_query_param("key")
    |> Accounts.get_user_by_api_key()
  end

  defp ensure_permission(opinion, user) do
    if Permissions.can_edit_opinion?(opinion, user) do
      :ok
    else
      {:error, :forbidden}
    end
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
