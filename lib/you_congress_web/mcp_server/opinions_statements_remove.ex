defmodule YouCongressWeb.MCPServer.OpinionsStatementsRemove do
  @moduledoc """
  Remove the association between an opinion and a statement through the MCP server.

  The caller must provide a valid API key via the `?key=` query param and have
  permission to manage statement opinions.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Ecto.Changeset
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Opinions
  alias YouCongress.Statements
  alias YouCongress.MCP.ToolUsageTracker

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @forbidden_message "Your account is not allowed to remove opinions from statements."
  @opinion_not_found "Opinion not found."
  @statement_not_found "Statement not found."
  @not_linked "Opinion is not associated with this statement."

  schema do
    field :opinion_id, :integer, required: true
    field :statement_id, :integer, required: true
  end

  @impl true
  def execute(%{opinion_id: opinion_id, statement_id: statement_id}, frame) do
    user_result = ToolUsageTracker.track(__MODULE__, frame)

    with {:ok, user} <- user_result,
         :ok <- ensure_permission(user),
         {:ok, opinion} <- fetch_opinion(opinion_id),
         {:ok, statement} <- fetch_statement(statement_id),
         {:ok, _} <- Opinions.remove_opinion_from_statement(opinion, statement) do
      data = %{
        opinion_id: opinion.id,
        statement_id: statement.id,
        statement_title: statement.title,
        statement_slug: statement.slug,
        removed: true
      }

      {:reply, Response.json(Response.tool(), data), frame}
    else
      {:error, :missing_api_key} ->
        {:reply, Response.error(Response.tool(), @missing_key_message), frame}

      {:error, :invalid_api_key} ->
        {:reply, Response.error(Response.tool(), @invalid_key_message), frame}

      {:error, :forbidden} ->
        {:reply, Response.error(Response.tool(), @forbidden_message), frame}

      {:error, :opinion_not_found} ->
        {:reply, Response.error(Response.tool(), @opinion_not_found), frame}

      {:error, :statement_not_found} ->
        {:reply, Response.error(Response.tool(), @statement_not_found), frame}

      {:error, :not_associated} ->
        {:reply, Response.error(Response.tool(), @not_linked), frame}

      {:error, :transaction_failed} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not remove opinion from statement due to an internal error."
         ), frame}

      {:error, %Changeset{} = changeset} ->
        {:reply,
         Response.error(
           Response.tool(),
           "Could not remove opinion from statement: #{format_changeset_errors(changeset)}"
         ), frame}
    end
  end

  defp ensure_permission(user) do
    if Permissions.can_add_opinion_to_statement?(user) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp fetch_opinion(opinion_id) do
    case Opinions.get_opinion(opinion_id) do
      nil -> {:error, :opinion_not_found}
      opinion -> {:ok, opinion}
    end
  end

  defp fetch_statement(statement_id) do
    case Statements.get_statement(statement_id) do
      nil -> {:error, :statement_not_found}
      statement -> {:ok, statement}
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
