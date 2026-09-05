defmodule YouCongressWeb.SEOMetaTest do
  @moduledoc """
  Dead-render checks for SEO meta tags and JSON-LD. Canonical links,
  meta descriptions and structured data only matter for crawlers, which
  see the dead render, so these use plain GETs, not live/2.
  """
  use YouCongressWeb.ConnCase

  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.HallsStatements
  alias YouCongress.Opinions

  describe "author page" do
    test "question-format title, canonical to /x/, Person JSON-LD", %{conn: conn} do
      author = author_fixture(%{name: "Jane Expert", twitter_username: "janex"})

      conn = get(conn, ~p"/a/#{author.id}")
      html = html_response(conn, 200)

      assert html =~ "What does Jane Expert say about AI? | YouCongress"

      assert html =~
               ~s(<link rel="canonical" href="#{YouCongressWeb.Endpoint.url()}/x/janex">)

      assert html =~ ~s("@type":"Person")
      assert html =~ ~s("name":"Jane Expert")
      refute html =~ ~s(<meta name="robots" content="noindex")

      assert_social_card(
        html,
        "/images/social-author.png",
        "Sourced quotes and positions from Jane Expert on YouCongress",
        1730
      )
    end

    test "nameless author is noindexed", %{conn: conn} do
      author_fixture(%{name: nil, bio: nil, twin_origin: false, twitter_username: "ghostuser"})

      conn = get(conn, ~p"/x/ghostuser")
      html = html_response(conn, 200)

      assert html =~ ~s(<meta name="robots" content="noindex")
      refute html =~ ~s("@type":"Person")
    end
  end

  describe "statement page" do
    test "statement description, Quotation JSON-LD without twins, blockquote markup", %{
      conn: conn
    } do
      statement = statement_fixture(%{title: "AI labs should publish safety frameworks"})

      human = author_fixture(%{name: "Human Quoter"})

      human_opinion =
        opinion_fixture(%{
          author_id: human.id,
          twin: false,
          content: "Real sourced quote text",
          source_url: "https://example.com/real"
        })

      {:ok, _} = Opinions.add_opinion_to_statement(human_opinion, statement)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: human.id,
        opinion_id: human_opinion.id,
        answer: :for,
        twin: false
      })

      twin_author = author_fixture(%{name: "Twin Author"})

      twin_opinion =
        opinion_fixture(%{
          author_id: twin_author.id,
          twin: true,
          content: "Twin generated text",
          source_url: "https://example.com/twin"
        })

      {:ok, _} = Opinions.add_opinion_to_statement(twin_opinion, statement)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: twin_author.id,
        opinion_id: twin_opinion.id,
        answer: :against,
        twin: true
      })

      conn = get(conn, ~p"/p/#{statement.slug}")
      html = html_response(conn, 200)

      document = Floki.parse_document!(html)

      for selector <- [
            ~s(meta[name="description"]),
            ~s(meta[property="og:description"]),
            ~s(meta[name="twitter:description"])
          ] do
        assert Floki.attribute(document, selector, "content") ==
                 ["See who's for and against, with sourced quotes, votes and original sources."]
      end

      for selector <- [~s(meta[property="og:title"]), ~s(meta[name="twitter:title"])] do
        assert [title] = Floki.attribute(document, selector, "content")
        assert title =~ statement.title
      end

      refute html =~ "% for,"
      refute html =~ "2 sourced quotes"

      assert html =~
               ~s(<link rel="canonical" href="#{YouCongressWeb.Endpoint.url()}/p/#{statement.slug}">)

      [_, json] =
        Regex.run(~r{<script type="application/ld\+json">\s*(.+?)\s*</script>}s, html)

      assert json =~ ~s("@type":"Quotation")
      assert json =~ "Real sourced quote text"
      refute json =~ "Twin generated text"

      assert html =~ ~s(<blockquote cite="https://example.com/real")
      refute html =~ ~s(<blockquote cite="https://example.com/twin")

      assert_social_card(
        html,
        "/images/social-statement.png",
        "Sourced positions for and against: AI labs should publish safety frameworks"
      )
    end
  end

  describe "hall page" do
    test "topic-hub title, H1, stats and CollectionPage JSON-LD", %{conn: conn} do
      statement = statement_fixture(%{title: "An AI safety statement"})
      {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "ai-safety", other_tags: []})

      conn = get(conn, ~p"/h/ai-safety")
      html = html_response(conn, 200)

      assert html =~ "Expert opinions on AI Safety | YouCongress"
      assert html =~ ~r{<h1[^>]*>\s*Expert opinions on AI Safety\s*</h1>}
      assert html =~ "1 policy proposals and claims"
      assert html =~ ~s("@type":"CollectionPage")

      assert html =~
               ~s(<link rel="canonical" href="#{YouCongressWeb.Endpoint.url()}/h/ai-safety">)
    end

    test "unknown hall still renders an H1 without stats", %{conn: conn} do
      conn = get(conn, ~p"/h/some-unknown-hall")
      html = html_response(conn, 200)

      assert html =~ ~r{<h1[^>]*>\s*Expert opinions on Some Unknown Hall\s*</h1>}
      refute html =~ ~s("@type":"CollectionPage")
    end

    test "Spanish Congress hall uses its search-friendly name", %{conn: conn} do
      conn = get(conn, ~p"/h/congreso-es")
      html = html_response(conn, 200)

      assert html =~ "Expert opinions on the Spanish Congress | YouCongress"
      assert html =~ ~r{<h1[^>]*>\s*Expert opinions on the Spanish Congress\s*</h1>}
      refute html =~ "Expert opinions on Congreso Es"
    end

    test "US Congress hall uses its search-friendly name", %{conn: conn} do
      conn = get(conn, ~p"/h/us-congress")
      html = html_response(conn, 200)

      assert html =~ "Expert opinions on the US Congress | YouCongress"
      assert html =~ ~r{<h1[^>]*>\s*Expert opinions on the US Congress\s*</h1>}
      refute html =~ "Expert opinions on US Congress"
    end
  end

  describe "home page" do
    test "has social-card metadata and WebSite + SearchAction JSON-LD", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      title = "What's new in AI governance, safety, jobs and society | YouCongress"
      escaped_title = title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      description =
        "Follow the latest sourced positions from experts, policymakers and public figures on AI governance, safety, jobs and society."

      assert html =~ ~s(<title>#{escaped_title}</title>)
      assert html =~ ~s(<meta content="#{escaped_title}" property="og:title")
      assert html =~ ~s(<meta name="twitter:title" content="#{escaped_title}")
      assert html =~ ~s(<meta name="description" content="#{description}")
      assert html =~ ~s(<meta content="#{description}" property="og:description")
      assert html =~ ~s(<meta name="twitter:description" content="#{description}")

      assert_social_card(
        html,
        "/images/social-home.png",
        "YouCongress latest sourced positions from experts, policymakers and public figures"
      )

      assert html =~ ~s("@type":"WebSite")
      assert html =~ "search_term_string"
    end
  end

  describe "explore page" do
    test "has dedicated social-card metadata", %{conn: conn} do
      conn = get(conn, ~p"/explore")
      html = html_response(conn, 200)

      assert html =~
               "<title>Explore sourced quotes, claims, people and topics | YouCongress</title>"

      assert html =~
               ~s(<meta name="description" content="Search sourced quotes and compare where experts, policymakers and citizens stand on consequential questions.")

      assert html =~ ~s(<link rel="canonical" href="#{YouCongressWeb.Endpoint.url()}/explore">)

      assert_social_card(
        html,
        "/images/social-explore.png",
        "Explore sourced quotes, public figures, policy statements and topics on YouCongress"
      )
    end
  end

  describe "opinion page" do
    test "quote page gets title, Quotation JSON-LD and blockquote", %{conn: conn} do
      author = author_fixture(%{name: "Quote Person"})

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          twin: false,
          content: "Some quoted words",
          source_url: "https://example.com/q",
          date: ~D[2024-01-01],
          date_precision: :year
        })

      conn = get(conn, ~p"/c/#{opinion.id}")
      html = html_response(conn, 200)

      assert html =~ "Quote Person on AI | YouCongress"
      assert html =~ ~s("@type":"Quotation")
      assert html =~ ~s(<blockquote cite="https://example.com/q")
      refute html =~ ~s(<meta name="robots" content="noindex")
    end

    test "plain comment is noindexed without JSON-LD", %{conn: conn} do
      author = author_fixture(%{name: "Commenter"})

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          twin: false,
          content: "just a comment",
          source_url: nil
        })

      conn = get(conn, ~p"/c/#{opinion.id}")
      html = html_response(conn, 200)

      assert html =~ ~s(<meta name="robots" content="noindex")
      refute html =~ "application/ld+json"
      refute html =~ "<blockquote"
    end
  end

  # Bluesky, LinkedIn and WhatsApp read the Open Graph fields; X reads the
  # twitter:* fields. Both families intentionally point at the same card.
  defp assert_social_card(html, image_path, alt, width \\ 1731) do
    image_url = YouCongressWeb.Endpoint.url() <> image_path

    assert html =~ ~s(<meta property="og:image" content="#{image_url}")
    assert html =~ ~s(<meta property="og:image:url" content="#{image_url}")
    assert html =~ ~s(<meta property="og:image:secure_url" content="#{image_url}")
    assert html =~ ~s(<meta property="og:image:type" content="image/png")
    assert html =~ ~s(<meta property="og:image:width" content="#{width}")
    assert html =~ ~s(<meta property="og:image:height" content="909")
    assert html =~ ~s(<meta property="og:image:alt" content="#{alt}")
    assert html =~ ~s(<meta name="twitter:card" content="summary_large_image")
    assert html =~ ~s(<meta name="twitter:image" content="#{image_url}")
    assert html =~ ~s(<meta name="twitter:image:alt" content="#{alt}")
  end
end
