defmodule YouCongressWeb.MCPServer.Search do
  @moduledoc "Search quotes, policy proposals, claims, authors, etc."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :query, :string, required: true
  end

  def execute(%{query: query}, frame) do
    {:reply, Response.json(Response.tool(), "Hello #{query}"), frame}
  end
end
