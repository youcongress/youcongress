defmodule YouCongressWeb.MCPServer do
  use Anubis.Server,
    name: "YouCongress",
    version: "1.0.0",
    capabilities: [:tools]

  # Tools
  component(YouCongressWeb.MCPServer.OpinionsSearch)
  component(YouCongressWeb.MCPServer.StatementsSearch)
  component(YouCongressWeb.MCPServer.StatementsList)
end
