defmodule YouCongressWeb.PageControllerTest do
  use YouCongressWeb.ConnCase, async: true

  import YouCongress.StatementsFixtures
  import YouCongress.OpinionsFixtures

  test "mission pages are public, linked, and have canonical metadata", %{conn: conn} do
    for {path, heading, linked_path} <- [
          {"/about", "Investigate difficult public questions.", "/theory-of-change"},
          {"/theory-of-change", "From shared evidence to better AI governance", "/moloch"}
        ] do
      html = conn |> get(path) |> html_response(200)
      document = Floki.parse_document!(html)
      assert Floki.text(Floki.find(document, "h1")) =~ heading
      assert length(Floki.find(document, "h1")) == 1

      assert Floki.attribute(document, "link[rel=canonical]", "href") ==
               [YouCongressWeb.Endpoint.url() <> path]

      assert Floki.attribute(document, "meta[name=description]", "content") != []
      assert Floki.find(document, "a[href='#{linked_path}']") != []
      assert Floki.find(document, "a[href='/explore']") != []
    end
  end

  describe "GET /status/24h" do
    test "returns OK for a positively verified quote dated today", %{conn: conn} do
      opinion_fixture(%{
        verification_status: :verified,
        date: Date.utc_today(),
        date_precision: :day
      })

      conn = get(conn, ~p"/status/24h")

      assert response(conn, 200) == "OK"
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end

    test "returns the latest positive quote date when no quote is recent", %{conn: conn} do
      latest_date = Date.add(Date.utc_today(), -2)

      opinion_fixture(%{
        verification_status: :verified,
        date: latest_date,
        date_precision: :day
      })

      opinion_fixture(%{
        verification_status: :disputed,
        date: Date.utc_today(),
        date_precision: :day
      })

      conn = get(conn, ~p"/status/24h")

      assert response(conn, 200) == Date.to_iso8601(latest_date)
    end

    test "reports that no dated verified quote exists", %{conn: conn} do
      opinion_fixture(%{verification_status: :verified, date: nil})

      conn = get(conn, ~p"/status/24h")

      assert response(conn, 200) == "No verified quote date available"
    end
  end

  test "GET / loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/")

    html = html_response(conn, 200)
    assert html =~ "YouCongress"
    refute html =~ ~s(id="cookie-banner")
    refute html =~ "Cookie settings"
  end

  test "GET / shows analytics choices to a logged-in user", %{conn: conn} do
    conn = conn |> log_in_as_user() |> get(~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s(id="cookie-banner")
    assert html =~ "we use optional analytics"
    assert html =~ "We only do this if you accept"
    assert html =~ "Cookie settings"
    refute html =~ "usage events to Amplitude"
  end

  test "GET /privacy loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    html = html_response(conn, 200)
    assert html =~ "Privacy Policy"
    assert html =~ "We do not send usage events to Amplitude unless you select"
    assert html =~ "We use Substack Inc. to manage newsletter subscriptions"
    assert html =~ "AI governance, AI safety, and the impact of AI on jobs"
    assert html =~ ~s(href="https://substack.com/privacy")
  end

  test "GET /terms loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms and Conditions"
  end

  test "GET /about loads as a non-logged visitor", %{conn: conn} do
    conn = get(conn, ~p"/about")
    html = html_response(conn, 200)

    assert html =~ "About YouCongress"
    assert html =~ ~s(href="https://www.linkedin.com/in/hectorperezarenas")
    assert html =~ ">Hector Perez Arenas</a>"
    assert html =~ ~s(href="/contact")
    assert html =~ "Contact us"
    assert html =~ ~s(href="/future-of-life-foundation-epistack-award")
  end

  test "GET /about loads as a user", %{conn: conn} do
    conn = log_in_as_user(conn)
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About YouCongress"
  end

  test "GET /future-of-life-foundation-epistack-award shows the award announcement", %{conn: conn} do
    conn = get(conn, ~p"/future-of-life-foundation-epistack-award")
    html = html_response(conn, 200)

    assert html =~ "YouCongress wins a $5,000 award"
    assert html =~ "https://youcongress.substack.com/p/our-youcongress-entry-won-a-5000"
    assert html =~ "https://flf.org/epistack-competition/"
    assert html =~ ~s(href="/h/flf-epistack")
    assert html =~ "https://www.oliversourbut.net/p/flfs-epistemic-case-study-competition"
    assert html =~ "https://www.oliversourbut.net/"

    assert html =~
             "https://forum.effectivealtruism.org/posts/eadfvJH8HBQLgdMKQ/flf-s-epistemic-case-study-competition-results"

    assert html =~
             "https://www.lesswrong.com/posts/mxzvL3hYFCcutQqcR/flf-s-epistemic-case-study-competition-results"

    assert html =~ ~s(src="/images/future-of-life-foundation-award.png")
    assert html =~ ~s(<meta property="og:type" content="article")

    assert html =~
             ~s(<meta property="og:image" content="#{YouCongressWeb.Endpoint.url()}/images/future-of-life-foundation-award.png")

    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image")

    assert html =~
             ~s(<meta name="twitter:image" content="#{YouCongressWeb.Endpoint.url()}/images/future-of-life-foundation-award.png")

    assert html =~
             ~s(<meta property="og:url" content="#{YouCongressWeb.Endpoint.url()}/future-of-life-foundation-epistack-award")
  end

  test "GET /faq loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/faq")
    html = html_response(conn, 200)

    assert html =~ "Frequently asked questions"
    assert html =~ "Who funds YouCongress?"
    assert html =~ ~s(href="https://www.linkedin.com/in/hectorperezarenas/")
    assert html =~ ~s(>self-funded</a>)
    assert html =~ ~s(href="/future-of-life-foundation-epistack-award")
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
    assert html =~ "https://youcongress.org/mcp?key=YOUR_API_KEY"
  end

  test "GET /mcp/claude shows the Claude setup guide", %{conn: conn} do
    conn = get(conn, ~p"/mcp/claude")
    html = html_response(conn, 200)

    assert html =~ "Use YouCongress from Claude"
    assert html =~ "Access write tools"
    assert html =~ "Authorization"
    assert html =~ "Bearer YOUR_API_KEY"
    assert html =~ "https://youcongress.org/mcp?key=YOUR_API_KEY"
    assert html =~ "Less safe"
    assert html =~ "Log In to Get Started"
  end

  test "GET /mcp/chatgpt shows the ChatGPT setup guide", %{conn: conn} do
    conn = get(conn, ~p"/mcp/chatgpt")
    html = html_response(conn, 200)

    assert html =~ "Use YouCongress from ChatGPT"
    assert html =~ "https://youcongress.org/mcp"
    assert html =~ "https://youcongress.org/mcp?key=YOUR_API_KEY"
    assert html =~ "Log In to Get Started"
  end

  test "GET /sitemap.xml lists statement URLs", %{conn: conn} do
    statement = statement_fixture(%{title: "Transparent AI policy"})

    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") == ["application/xml; charset=utf-8"]
    assert body =~ "<loc>#{YouCongressWeb.Endpoint.url()}#{~p"/reconsider"}</loc>"
    assert body =~ "<loc>#{YouCongressWeb.Endpoint.url()}#{~p"/moloch"}</loc>"
    assert body =~ "<loc>#{YouCongressWeb.Endpoint.url()}#{~p"/theory-of-change"}</loc>"
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
    assert body =~ "?key=YOUR_API_KEY"
  end
end
