defmodule YouCongressWeb.MCPServer.StatementHalls do
  @moduledoc """
  Return a single statement along with its halls.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements
  alias YouCongressWeb.MCPServer.StatementSerializer
  alias YouCongress.MCP.ToolUsageTracker

  @not_found_message "Statement not found."

  schema do
    field :statement_id, :integer, required: true
  end

  @impl true
  def execute(%{statement_id: statement_id}, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    case fetch_statement(statement_id) do
      nil ->
        {:reply, Response.error(Response.tool(), @not_found_message), frame}

      statement ->
        data = serialize_statement(statement)
        {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp fetch_statement(statement_id) do
    Statements.get_statement(statement_id, preload: [:halls])
  end

  defp serialize_statement(statement) do
    %{
      statement_id: statement.id,
      statement_title: statement.title,
      halls: StatementSerializer.halls(statement)
    }
  end
end
