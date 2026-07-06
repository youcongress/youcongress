defmodule YouCongressWeb.PageControllerTest do
  use YouCongressWeb.ConnCase, async: true

  import YouCongress.StatementsFixtures

  test "GET / loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "YouCongress"
  end

  test "GET /privacy loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "GET /terms loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms and Conditions"
  end

  test "GET /about loads as a non-logged visitor", %{conn: conn} do
    conn = get(conn, ~p"/about")
    html = html_response(conn, 200)

    assert html =~ "About YouCongress"
    assert html =~ ~s(href="/contact")
    assert html =~ "contact us"
  end

  test "GET /about loads as a user", %{conn: conn} do
    conn = log_in_as_user(conn)
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About YouCongress"
  end

  test "GET /faq loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/faq")
    assert html_response(conn, 200) =~ "Frequently asked questions"
  end

  test "GET /faq explains verification badge states", %{conn: conn} do
    conn = get(conn, ~p"/faq")
    html = html_response(conn, 200)

    assert html =~ "Endorsed"
    assert html =~ "Verified"
    assert html =~ "AI Verified"
    assert html =~ "Disputed"
    assert html =~ "Unverifiable"
    assert html =~ "AI Unverifiable"
    assert html =~ "Unverified"
  end

  test "GET /email-login-waiting-list", %{conn: conn} do
    conn = get(conn, ~p"/email-login-waiting-list")
    assert html_response(conn, 200) =~ "Waiting list for email/password login - YouCongress"
  end

  test "POST /email-login-waiting-list/thanks", %{conn: conn} do
    conn = get(conn, ~p"/email-login-waiting-list/thanks")
    assert html_response(conn, 302) =~ "redirected"
  end

  test "GET /mcp-tools shows the MCP reference page", %{conn: conn} do
    conn = get(conn, ~p"/mcp-tools")
    html = html_response(conn, 200)

    assert html =~ "YouCongress MCP Tools"
    assert html =~ "How to Connect"
  end

  test "GET /mcp/claude shows the Claude setup guide", %{conn: conn} do
    conn = get(conn, ~p"/mcp/claude")
    html = html_response(conn, 200)

    assert html =~ "Use YouCongress from Claude"
    assert html =~ "Log In to Get Started"
  end

  test "GET /mcp/chatgpt shows the ChatGPT setup guide", %{conn: conn} do
    conn = get(conn, ~p"/mcp/chatgpt")
    html = html_response(conn, 200)

    assert html =~ "Use YouCongress from ChatGPT"
    assert html =~ "https://youcongress.org/mcp"
    assert html =~ "Log In to Get Started"
  end

  test "GET /sitemap.xml lists statement URLs", %{conn: conn} do
    statement = statement_fixture(%{title: "Transparent AI policy"})

    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert body =~ "<loc>#{YouCongressWeb.Endpoint.url()}#{~p"/p/#{statement.slug}"}</loc>"
    assert body =~ ~r"<lastmod>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z</lastmod>"
  end

  test "GET /sitemap.xml includes quoted authors, halls and quote pages", %{conn: conn} do
    statement = statement_fixture(%{title: "Sitemap test statement"})

    {:ok, _} =
      YouCongress.HallsStatements.sync!(statement.id, %{main_tag: "ai-safety", other_tags: []})

    quoted_author =
      YouCongress.AuthorsFixtures.author_fixture(%{
        name: "Quoted Author",
        twitter_username: "quotedauthor"
      })

    quote_opinion =
      YouCongress.OpinionsFixtures.opinion_fixture(%{
        author_id: quoted_author.id,
        twin: false,
        source_url: "https://example.com/quote"
      })

    YouCongress.AuthorsFixtures.author_fixture(%{
      name: "Quoteless Author",
      twitter_username: "quotelessauthor"
    })

    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)
    base = YouCongressWeb.Endpoint.url()

    assert body =~ "<loc>#{base}/x/quotedauthor</loc>"
    refute body =~ "<loc>#{base}/x/quotelessauthor</loc>"
    assert body =~ "<loc>#{base}/h/ai-safety</loc>"
    assert body =~ "<loc>#{base}/c/#{quote_opinion.id}</loc>"
  end

  test "GET /llms.txt lists content sections and keeps the MCP docs", %{conn: conn} do
    statement = statement_fixture(%{title: "Llms statement title"})

    {:ok, _} =
      YouCongress.HallsStatements.sync!(statement.id, %{main_tag: "ai-safety", other_tags: []})

    author = YouCongress.AuthorsFixtures.author_fixture(%{name: "Llms Author"})

    YouCongress.OpinionsFixtures.opinion_fixture(%{
      author_id: author.id,
      twin: false,
      source_url: "https://example.com/llms"
    })

    conn = get(conn, ~p"/llms.txt")
    body = response(conn, 200)

    assert body =~ "## Topics"
    assert body =~ "[AI Safety]("
    assert body =~ "## Key authors"
    assert body =~ "[Llms Author]("
    assert body =~ "## Top statements"
    assert body =~ "Llms statement title"
    assert body =~ "## MCP server (for AI agents)"
    assert body =~ url(~p"/mcp")
  end
end
