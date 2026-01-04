defmodule YouCongressWeb.MCPServer.StatementsList do
  @moduledoc """
  Search statements (policy proposals and claims).
  You may use the statement_id to search quotes later.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements

  schema do
  end

  def execute(_, frame) do
    statements =
      [limit: 100]
      |> Statements.list_statements()
      |> Enum.map(fn statement ->
        %{
          title: statement.title,
          id: statement.id
        }
      end)

    data = %{
      statements: statements
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end
end
