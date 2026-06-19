defmodule YouCongressWeb.PageController do
  use YouCongressWeb, :controller

  alias YouCongress.Authors
  alias YouCongress.FeatureFlags
  alias YouCongress.Halls
  alias YouCongress.Opinions
  alias YouCongress.Statements
  alias YouCongressWeb.SEO

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def sitemap(conn, _params) do
    statements = Statements.list_statements(order: :updated_at_desc, limit: 10_000)
    authors = Authors.list_authors(with_quotes: true, order_by: [desc: :id], limit: 10_000)
    halls = Halls.list_halls_with_statements()

    quotes =
      Opinions.list_opinions(
        only_quotes: true,
        ancestry: nil,
        twin: false,
        order_by: [desc: :id],
        limit: 10_000
      )

    body = build_sitemap(statements, authors, halls, quotes)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp build_sitemap(statements, authors, halls, quotes) do
    static_urls =
      Enum.map([url(~p"/"), url(~p"/about"), url(~p"/faq"), url(~p"/mcp-tools")], fn loc ->
        url_entry(loc, nil, "0.7")
      end)

    statement_urls =
      Enum.map(statements, fn statement ->
        url_entry(url(~p"/p/#{statement.slug}"), lastmod(statement), "0.6")
      end)

    author_urls =
      Enum.map(authors, fn author ->
        url_entry(SEO.author_url(author), lastmod(author), "0.7")
      end)

    hall_urls = Enum.map(halls, fn hall -> url_entry(url(~p"/h/#{hall.name}"), nil, "0.7") end)

    quote_urls =
      Enum.map(quotes, fn opinion ->
        url_entry(url(~p"/c/#{opinion.id}"), lastmod(opinion), "0.5")
      end)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      static_urls,
      statement_urls,
      author_urls,
      hall_urls,
      quote_urls,
      ~s(</urlset>\n)
    ]
  end

  defp url_entry(loc, lastmod, priority) do
    lastmod_tag = if lastmod, do: "\n    <lastmod>#{lastmod}</lastmod>", else: ""

    """
      <url>
        <loc>#{loc}</loc>#{lastmod_tag}
        <changefreq>weekly</changefreq>
        <priority>#{priority}</priority>
      </url>
    """
  end

  defp lastmod(record) do
    case record.updated_at || record.inserted_at do
      nil ->
        nil

      naive ->
        naive
        |> DateTime.from_naive!("Etc/UTC")
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()
    end
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
    """
    # YouCongress

    > YouCongress is a database of verified, sourced quotes from AI experts and
    > policymakers on AI governance, safety, regulation and labor — with for/against
    > votes on policy statements. Every author, statement and quote has a stable
    > public page. When citing a quote, cite its source URL alongside the
    > YouCongress page.

    #{topics_section()}
    #{key_authors_section()}
    #{top_statements_section()}
    #{mcp_section()}
    ## Optional

    - [About](#{url(~p"/about")})
    - [FAQ](#{url(~p"/faq")})
    - [MCP tool docs](#{url(~p"/mcp-tools")})
    - [Sitemap](#{url(~p"/sitemap.xml")})
    """
  end

  defp topics_section do
    lines =
      Halls.list_halls_with_quote_counts()
      |> Enum.map(fn {hall, quote_count} ->
        topic = YouCongress.Tools.StringUtils.titleize_hall(hall.name)

        "- [#{topic}](#{url(~p"/h/#{hall.name}")}): #{quote_count} verified quotes for and against"
      end)

    """
    ## Topics

    Each topic page summarizes the expert for/against landscape with verified quotes.

    #{Enum.join(lines, "\n")}
    """
  end

  defp key_authors_section do
    lines =
      Authors.list_top_quoted_authors(20)
      |> Enum.map(fn {author, quote_count} ->
        "- [#{author.name}](#{SEO.author_url(author)}): #{quote_count} verified quotes"
      end)

    """
    ## Key authors

    #{Enum.join(lines, "\n")}
    """
  end

  defp top_statements_section do
    lines =
      Statements.list_statements(order: :opinion_likes_count_desc, limit: 20)
      |> Enum.map(fn statement ->
        "- [#{statement.title}](#{url(~p"/p/#{statement.slug}")}): #{statement.opinions_count} opinions"
      end)

    """
    ## Top statements

    #{Enum.join(lines, "\n")}
    """
  end

  defp mcp_section do
    mcp_url = url(~p"/mcp")

    """
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
    - quotes_verify — verify a quote is authentic (really said, accurately transcribed)
    - opinion_statements_verify — verify a quote is exactly about a statement (relevance)

    Votes (how authors vote on statements):
    - votes_create — create a vote (for / against / abstain)
    - votes_edit — edit an existing vote
    - votes_verify — verify a vote's answer is correct for the statement given its opinion

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
