defmodule YouCongressWeb.MCPServer.StatementsList do
  @moduledoc """
  List statements (policy proposals and claims) so, later, with the 'quotes_search' tool you can search quotes.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias YouCongress.Statements
  alias YouCongressWeb.MCPServer.StatementSerializer
  alias YouCongress.MCP.ToolUsageTracker

  schema do
    field :include_halls, :boolean, default: false
  end

  @limit 100

  def execute(params, frame) do
    ToolUsageTracker.track(__MODULE__, frame)

    include_halls? = Map.get(params, :include_halls, false)

    statements =
      [limit: @limit]
      |> maybe_include_halls(include_halls?)
      |> Statements.list_statements()
      |> Enum.map(&serialize_statement(&1, include_halls?))

    data = %{
      statements: statements
    }

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp maybe_include_halls(opts, true) do
    existing = Keyword.get(opts, :preload, []) |> List.wrap()
    Keyword.put(opts, :preload, Enum.uniq([:halls | existing]))
  end

  defp maybe_include_halls(opts, _include_halls), do: opts

  defp serialize_statement(statement, include_halls?) do
    base = %{
      title: statement.title,
      id: statement.id,
      opinions_count: statement.opinions_count
    }

    if include_halls? do
      Map.put(base, :halls, StatementSerializer.halls(statement))
    else
      base
    end
  end
end
