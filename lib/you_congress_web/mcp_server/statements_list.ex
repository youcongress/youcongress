defmodule YouCongressWeb.MCPServer.StatementsList do
  @moduledoc """
  List statements (policy proposals and claims) so, later, with the 'quotes_search' tool you can search quotes.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements

  schema do
  end

  @limit 100

  def execute(_, frame) do
    statements =
      [limit: @limit]
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
