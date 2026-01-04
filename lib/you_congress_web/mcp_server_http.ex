defmodule YouCongressWeb.MCPServerHTTP do
  use Anubis.Server,
    name: "YouCongress",
    version: "1.0.0",
    capabilities: [:tools]

  # Tools
  component(YouCongressWeb.MCPServer.Search)
end
