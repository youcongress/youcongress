defmodule YouCongressWeb.MCPServer do
  use Anubis.Server,
    name: "YouCongress",
    version: "1.0.0",
    capabilities: [:tools]

  # Tools: when adding or changing tools, also update the human docs at /mcp-tools
  # (lib/you_congress_web/controllers/page_html/mcp_tools.html.heex) and the
  # AI-facing tool list in build_llms_txt/0 (page_controller.ex, served at /llms.txt).
  # component(YouCongressWeb.MCPServer.StatementsSearch)
  component(YouCongressWeb.MCPServer.StatementsCreate)
  # Disabled statement populate as it's not working as well as the fresh quote discovery
  # component(YouCongressWeb.MCPServer.StatementPopulate)
  component(YouCongressWeb.MCPServer.StatementsList)
  component(YouCongressWeb.MCPServer.StatementHalls)
  component(YouCongressWeb.MCPServer.StatementAuthors)
  component(YouCongressWeb.MCPServer.StatementsHallsUpdate)
  component(YouCongressWeb.MCPServer.AuthorsSearch)
  component(YouCongressWeb.MCPServer.AuthorsList)
  component(YouCongressWeb.MCPServer.AuthorsCreate)
  component(YouCongressWeb.MCPServer.AuthorsUpdate)
  component(YouCongressWeb.MCPServer.QuotesSearch)
  component(YouCongressWeb.MCPServer.QuotesList)
  component(YouCongressWeb.MCPServer.QuotesRandomUnverified)
  component(YouCongressWeb.MCPServer.QuotesRecentUnverified)
  component(YouCongressWeb.MCPServer.OpinionsShow)
  component(YouCongressWeb.MCPServer.OpinionsCreate)
  component(YouCongressWeb.MCPServer.OpinionsEdit)
  component(YouCongressWeb.MCPServer.OpinionsDelete)
  component(YouCongressWeb.MCPServer.OpinionsStatementsAdd)
  component(YouCongressWeb.MCPServer.OpinionsStatementsRemove)
  component(YouCongressWeb.MCPServer.QuotesVerify)
  component(YouCongressWeb.MCPServer.OpinionStatementsVerify)
  component(YouCongressWeb.MCPServer.VotesVerify)
  component(YouCongressWeb.MCPServer.VotesCreate)
  component(YouCongressWeb.MCPServer.VotesEdit)
end
