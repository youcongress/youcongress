defmodule YouCongressWeb.MCPServer do
  use Anubis.Server,
    name: "YouCongress",
    version: "1.0.0",
    capabilities: [:tools]

  # Tools
  # component(YouCongressWeb.MCPServer.StatementsSearch)
  component(YouCongressWeb.MCPServer.StatementsCreate)
  component(YouCongressWeb.MCPServer.StatementsList)
  component(YouCongressWeb.MCPServer.AuthorsSearch)
  component(YouCongressWeb.MCPServer.AuthorsCreate)
  component(YouCongressWeb.MCPServer.AuthorsUpdate)
  component(YouCongressWeb.MCPServer.QuotesSearch)
  component(YouCongressWeb.MCPServer.QuotesRandomUnverified)
  component(YouCongressWeb.MCPServer.OpinionsShow)
  component(YouCongressWeb.MCPServer.OpinionsCreate)
  component(YouCongressWeb.MCPServer.OpinionsEdit)
  component(YouCongressWeb.MCPServer.OpinionsDelete)
  component(YouCongressWeb.MCPServer.OpinionsStatementsAdd)
  component(YouCongressWeb.MCPServer.OpinionsStatementsRemove)
  component(YouCongressWeb.MCPServer.QuotesVerify)
  component(YouCongressWeb.MCPServer.VotesCreate)
  component(YouCongressWeb.MCPServer.VotesEdit)
end
