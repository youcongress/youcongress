defmodule YouCongressWeb.MCPServer.StatementsSearch do
  @moduledoc """
  Search statements (policy proposals and claims) on YouCongress.
  Each statement has quotes from experts and public figures in favour and against.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements

  @limit 100

  schema do
    field :query, :string, required: true
  end

  def execute(%{query: query}, frame) do
    statements = find_statements(query)
    more_statements = more_statements(statements)

    data = %{
      matches: statements,
      more_statements: more_statements
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp find_statements(query) do
    [search: query, limit: @limit]
    |> Statements.list_statements()
    |> take_fields()
  end

  defp more_statements(statements) do
    statement_ids = Enum.map(statements, & &1.id)
    exact_count = length(statement_ids)

    [limit: @limit - exact_count, exclude_ids: statement_ids]
    |> Statements.list_statements()
    |> take_fields()
  end

  defp take_fields(statements) do
    Enum.map(statements, fn statement ->
      %{
        statement_id: statement.id,
        title: statement.title
      }
    end)
  end
end
