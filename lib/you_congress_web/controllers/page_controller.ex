defmodule YouCongressWeb.PageController do
  use YouCongressWeb, :controller

  alias YouCongress.FeatureFlags
  alias YouCongress.Statements

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def sitemap(conn, _params) do
    statements = Statements.list_statements(order: :updated_at_desc, limit: 1_000)
    body = build_sitemap(statements)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp build_sitemap(statements) do
    urls =
      Enum.map(statements, fn statement ->
        lastmod =
          (statement.updated_at || statement.inserted_at)
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.truncate(:second)
          |> DateTime.to_iso8601()

        loc = url(~p"/p/#{statement.slug}")

        """
          <url>
            <loc>#{loc}</loc>
            <lastmod>#{lastmod}</lastmod>
            <changefreq>weekly</changefreq>
            <priority>0.6</priority>
          </url>
        """
      end)

    static_urls =
      Enum.map([url(~p"/"), url(~p"/about"), url(~p"/faq"), url(~p"/mcp-tools")], fn loc ->
        """
          <url>
            <loc>#{loc}</loc>
            <changefreq>weekly</changefreq>
            <priority>0.7</priority>
          </url>
        """
      end)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      static_urls,
      urls,
      ~s(</urlset>\n)
    ]
  end

  def waiting_list(conn, _params) do
    render(conn, :waiting_list, layout: false)
  end

  def about(conn, _params) do
    render(conn, :about,
      search: nil,
      search_tab: :quotes,
      halls: [],
      authors: [],
      statements: [],
      quotes: [],
      log_in_with_x_enabled: FeatureFlags.enabled?(:log_in_with_x)
    )
  end

  def faq(conn, _params) do
    render(conn, :faq)
  end

  def mcp_tools(conn, _params) do
    render(conn, :mcp_tools)
  end

  # Machine-readable site description for AI assistants/agents.
  # See https://llmstxt.org/. Advertises the MCP server so AIs visiting the
  # site discover the tools without a human having to configure them.
  def llms_txt(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, build_llms_txt())
  end

  # When changing the tool list here, also update the human docs at /mcp-tools
  # (page_html/mcp_tools.html.heex) — and vice versa.
  defp build_llms_txt do
    mcp_url = url(~p"/mcp")

    """
    # YouCongress

    > YouCongress is a platform of statements (policy proposals and claims) that
    > people and AIs vote on, backed by sourced quotes attributed to real authors.
    > It exposes its data and actions through a Model Context Protocol (MCP) server,
    > so AI assistants can browse statements, search authors and quotes, verify
    > sources, and record opinions and votes directly.

    ## MCP server (for AI agents)

    If you are an AI assistant, connect to the YouCongress MCP server to interact
    with the platform programmatically. No API key is required for public,
    read-only tools; a key (from the user's Settings page) unlocks write access.

    - MCP endpoint (Streamable HTTP): #{mcp_url}
    - With a key: #{mcp_url}?key=YOUR_API_KEY
    - Human-readable tool docs: #{url(~p"/mcp-tools")}
    - Claude setup guide: #{url(~p"/mcp/claude")}

    ### Available tools

    Statements (policy proposals/claims people vote on):
    - statements_list — list statements; find statement IDs for other tools
    - statement_halls — a statement's halls (topics) by ID
    - statement_authors — authors with a sourced quote on a statement
    - statements_create — create a statement (creator/admin)
    - statement_populate — queue AI quote discovery for a statement (admin)
    - statements_halls_update — set the halls on a statement (own/admin)

    Authors (people whose opinions and votes are tracked):
    - authors_search — search authors by name
    - authors_list — list authors, filterable by country
    - authors_create — create an author (moderator/creator/admin)
    - authors_update — update an author (moderator/creator/admin)

    Opinions (quotes/positions attributed to authors, linked to statements):
    - opinions_show — view an opinion with its statements and votes
    - opinions_create — create an opinion; include source_url to make it a quote
    - opinions_edit — edit an opinion
    - opinions_delete — delete an opinion
    - opinions_statements_add — link an opinion to a statement and set the vote
    - opinions_statements_remove — unlink an opinion from a statement

    Quotes & verification (sourced opinions):
    - quotes_search — keyword search within a statement, or semantic search across all quotes
    - quotes_list — list quotes with author, source, status and vote
    - quotes_random_unverified — a random unverified quote to review
    - quotes_recent_unverified — the most recent unverified quote to review
    - quotes_verify — record a verification verdict for a quote

    Votes (how authors vote on statements):
    - votes_create — create a vote (for / against / abstain)
    - votes_edit — edit an existing vote

    ## What you can do

    - Find sourced quotes for a statement and add them via the opinions and votes tools.
    - Help review and verify unverified quotes against their sources.
    - Browse what real people and AIs think about a policy proposal.
    """
  end

  def mcp_claude(conn, _params) do
    render(conn, :mcp_claude)
  end

  def mcp_chatgpt(conn, _params) do
    render(conn, :mcp_chatgpt)
  end

  def redirect_to_questions(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  def redirect_to_home(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  def email_login_waiting_list(conn, _params) do
    render(conn, :email_login_waiting_list, layout: false)
  end

  def email_login_waiting_list_thanks(conn, _params) do
    conn
    |> put_flash(:info, "Thanks for joining the waiting list! We'll be in touch.")
    |> redirect(to: ~p"/")
  end
end
