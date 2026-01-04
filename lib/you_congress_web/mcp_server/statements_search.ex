defmodule YouCongressWeb.MCPServer.StatementsSearch do
  @moduledoc "Search statements on YouCongress."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements

  schema do
    field :query, :string, required: true
  end

  def execute(%{query: query}, frame) do
    statements =
      [search: query, limit: 100]
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
