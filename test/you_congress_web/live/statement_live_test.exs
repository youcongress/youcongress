defmodule YouCongressWeb.StatementLiveTest do
  use YouCongressWeb.ConnCase

  import Mock

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures
  import YouCongress.DelegationsFixtures

  alias YouCongress.Statements
  alias YouCongress.HallsStatements
  alias YouCongress.Opinions
  alias YouCongress.Likes

  @create_attrs %{title: "nuclear energy"}
  @suggested_titles [
    %{
      title: "Should we increase investment in nuclear energy research?",
      slug: "increase-investment-nuclear-energy"
    },
    %{
      title: "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
      slug: "nuclear-energy-alternative-fossil"
    },
    %{
      title: "Could nuclear energy be a key solution for reducing global carbon emissions?",
      slug: "nuclear-energy-key-solution"
    }
  ]
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_statement(_) do
    statement = statement_fixture()
    {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "ai", other_tags: []})

    %{statement: statement}
  end

  defp occurrences(string, substring), do: length(:binary.matches(string, substring))

  defp create_statement_with_top_opinion(title, likes_count) do
    statement = statement_fixture(%{title: title})
    {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "ai", other_tags: []})

    author = author_fixture()
    opinion = opinion_fixture(%{author_id: author.id})
    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)
    vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})
    fill_statement_with_quotes(statement.id)
    {:ok, _} = Opinions.update_opinion(opinion, %{likes_count: likes_count})

    %{statement: statement, likes: likes_count}
  end

  describe "Index" do
    setup [:create_statement]

    test "vote and create opinion", %{conn: conn, statement: statement} do
      # Create an opinion so the statement appears in "New" mode
      author = author_fixture()
      opinion = opinion_fixture(%{author_id: author.id, content: "Test opinion"})

      _vote =
        vote_fixture(%{statement_id: statement.id, author_id: author.id, opinion_id: opinion.id})

      fill_statement_with_quotes(statement.id)

      conn = log_in_as_user(conn)
      {:ok, index_live, html} = live(conn, ~p"/")

      assert html =~ statement.title

      # Vote For
      index_live
      |> element("button[id$='-vote-for']")
      |> render_click()

      assert index_live |> element("button[id$='-vote-for']") |> render() =~ "✓"
      assert index_live |> element("button[id$='-vote-for']") |> render() =~ "For"

      # Vote Against
      index_live
      |> element("button[id$='-vote-against']")
      |> render_click()

      assert index_live |> element("button[id$='-vote-against']") |> render() =~ "✓"
      assert index_live |> element("button[id$='-vote-against']") |> render() =~ "Against"

      # Vote Abstain
      index_live
      |> element("button[id$='-vote-abstain']")
      |> render_click()

      assert index_live |> element("button[id$='-vote-abstain']") |> render() =~ "✓"
      assert index_live |> element("button[id$='-vote-abstain']") |> render() =~ "Abstain"

      # Create a comment
      index_live
      |> form("#v#{statement.id}-opinion-form", %{"opinion[content]" => "some comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion created successfully"
      assert html =~ "some comment"

      index_live
      |> form("#v#{statement.id}-opinion-form", %{"opinion[content]" => "some updated comment"})
      |> render_submit()

      html = render(index_live)
      assert html =~ "Opinion updated successfully"
      assert html =~ "some updated comment"
    end

    test "loads country vote results on home only after clicking by country", %{
      conn: conn,
      statement: statement
    } do
      unique = System.unique_integer([:positive])
      quote_country = country_fixture(%{name: "Home Quote Country #{unique}"})
      voter_country = country_fixture(%{name: "Home Voter Country #{unique}"})

      author = author_fixture(%{country_id: quote_country.id})
      opinion = opinion_fixture(%{author_id: author.id, content: "Country test opinion"})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        opinion_id: opinion.id,
        answer: :against
      })

      fill_statement_with_quotes(statement.id)

      current_user =
        user_fixture(%{}, %{
          name: "Home Voter #{unique}",
          twitter_username: "home_voter_#{unique}",
          bio: "Bio",
          wikipedia_url: "https://en.wikipedia.org/wiki/Home_Voter_#{unique}",
          twin_origin: false,
          country_id: voter_country.id
        })

      conn = log_in_user(conn, current_user)
      {:ok, index_live, html} = live(conn, ~p"/")

      assert html =~ statement.title
      refute html =~ voter_country.name

      html =
        index_live
        |> element("button[id$='-vote-for']")
        |> render_click()

      assert html =~ "By country"
      refute html =~ voter_country.name

      html =
        index_live
        |> element("button[id$='-results-by-country']", "By country")
        |> render_click()

      assert html =~ voter_country.name
      assert html =~ quote_country.name
    end

    test "Top mode orders cards by most liked opinions", %{conn: conn} do
      data =
        [
          {"Most liked opinion", 30},
          {"Second place opinion", 20},
          {"Third place opinion", 10}
        ]
        |> Enum.map(fn {title, likes} -> create_statement_with_top_opinion(title, likes) end)

      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("button[phx-click='toggle-switch']") |> render_click()
      top_html = render(view)

      expected_order = Enum.sort_by(data, & &1.likes, :desc)

      indexes =
        Enum.map(expected_order, fn %{statement: statement} ->
          case :binary.match(top_html, statement.title) do
            {pos, _length} -> pos
            :nomatch -> flunk("Expected to find #{statement.title} on Top mode feed")
          end
        end)

      assert indexes == Enum.sort(indexes)
    end

    test "saves new statement and redirect to show", %{conn: conn} do
      with_mocks([
        {YouCongress.Statements.TitleRewording, [],
         [generate_rewordings: fn _, _ -> {:ok, @suggested_titles, 0} end]}
      ]) do
        conn = log_in_as_admin(conn)
        {:ok, index_live, _html} = live(conn, ~p"/")

        index_live
        |> element("button#create-poll-button", "New")
        |> render_click()

        assert index_live
               |> form("#statement-form", statement: @invalid_attrs)
               |> render_change() =~ "can&#39;t be blank"

        [suggestion1, suggestion2, _suggestion3] = @suggested_titles

        assert index_live
               |> form("#statement-form", statement: @create_attrs)
               |> render_submit() =~ suggestion1.title

        response =
          index_live
          |> element("button", suggestion2.title)
          |> render_click()

        statement = Statements.get_statement!(title: suggestion2.title)
        statement_path = ~p"/p/#{statement.slug}"

        {_, {:redirect, %{to: ^statement_path}}} = response
      end
    end
  end

  describe "Show" do
    setup [:create_statement]

    test "displays statement as logged user", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ statement.title
    end

    test "displays statement as non-logged visitor", %{conn: conn, statement: statement} do
      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ statement.title
    end

    test "source link underline does not include the date separator", %{
      conn: conn,
      statement: statement
    } do
      author = author_fixture()

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          content: "Sourced opinion with date",
          source_url: "https://example.com/source-whitespace",
          date: ~D[2026-01-01],
          date_precision: :month,
          twin: false
        })

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: opinion.id,
          answer: :for,
          twin: false
        })

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()

      assert card_html =~
               ~r/<a[^>]+href="https:\/\/example\.com\/source-whitespace"[^>]*>source<\/a>\s*<\/span>\s*<span[^>]*>\(Jan 2026\)<\/span>/
    end

    test "shows vote results to non-logged visitors without voting", %{
      conn: conn,
      statement: statement
    } do
      author = author_fixture()

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        answer: :for
      })

      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Results (1 vote):"
      assert html =~ "For 1 (100%)"
      assert html =~ "By country"
    end

    test "guest vote auth modal keeps the statement page as return_to", %{
      conn: conn,
      statement: statement
    } do
      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      show_live
      |> element("button#cast-vote-for", "For")
      |> render_click()

      html = render(show_live)
      assert html =~ "vote-auth-modal"
      assert html =~ "return_to=%2Fp%2F#{statement.slug}"
    end

    test "shows voting and opinion controls without existing votes", %{
      conn: conn,
      statement: statement
    } do
      conn = log_in_as_user(conn)

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Cast your vote:"
      assert has_element?(show_live, "button#cast-vote-for", "For")
      assert has_element?(show_live, "button#cast-vote-abstain", "Abstain")
      assert has_element?(show_live, "button#cast-vote-against", "Against")
      assert has_element?(show_live, "#comment-form")

      show_live
      |> form("#comment-form", comment: "first comment on an empty statement")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Comment created successfully"
      assert html =~ "first comment on an empty statement"
    end

    test "shows statement header actions", %{
      conn: conn,
      statement: statement
    } do
      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Add quotes manually"
      assert html =~ ~s(href="/p/#{statement.slug}/add-quote")
      assert html =~ "Invite others"
      assert html =~ "data-copy-current-url"
      assert html =~ "Add quotes with AI"
      login_path = "/log_in?return_to=%2Fp%2F#{statement.slug}"
      assert has_element?(show_live, "a[href='#{login_path}']", "Add quotes with AI")
      assert html =~ ~s(href="#{login_path}")
      refute html =~ "Find quotes"
      refute html =~ "Biased? Add more"
    end

    test "header sign up link keeps the statement page as return_to", %{
      conn: conn,
      statement: statement
    } do
      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ ~s(href="/sign_up?return_to=%2Fp%2F#{statement.slug}")
    end

    test "shows credit purchase message when AI quote action needs permission", %{
      conn: conn,
      statement: statement
    } do
      conn = log_in_as_user(conn)

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Add quotes with AI"

      html =
        show_live
        |> element("button[phx-click='find-sourced-quotes']", "Add quotes with AI")
        |> render_click()

      assert html =~
               "AI quote search uses credits. Email hello@youcongress.org to purchase access."
    end

    test "shows AI quote action to users with permission", %{
      conn: conn,
      statement: statement
    } do
      conn = log_in_as_creator(conn)

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Add quotes with AI"

      assert has_element?(
               show_live,
               "button[phx-click='find-sourced-quotes']",
               "Add quotes with AI"
             )

      refute html =~ "Find quotes"
    end

    test "updates statement within modal", %{conn: conn, statement: statement} do
      conn = log_in_as_admin(conn)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Poll"

      assert_patch(show_live, ~p"/p/#{statement.slug}/show/edit")

      assert show_live
             |> form("#statement-form", statement: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#statement-form", statement: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/p/#{statement.slug}")

      html = render(show_live)
      assert html =~ "Statement updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes statement in listing", %{conn: conn, statement: statement} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/p/#{statement.slug}/edit")

      index_live
      |> element("a", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Statements.get_statement!(statement.id)
      end
    end

    test "casts a vote from statement buttons", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      opinion = opinion_fixture(%{statement_id: statement.id})
      # Create a vote so we display the voting options
      vote_fixture(%{statement_id: statement.id, opinion_id: opinion.id})

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      # Vote For
      show_live
      |> element("button#cast-vote-for")
      |> render_click()

      assert show_live |> element("button#cast-vote-for") |> render() =~ "✓"
      assert show_live |> element("button#cast-vote-for") |> render() =~ "For"

      # Vote Against
      show_live
      |> element("button#cast-vote-against")
      |> render_click()

      assert show_live |> element("button#cast-vote-against") |> render() =~ "✓"
      assert show_live |> element("button#cast-vote-against") |> render() =~ "Against"

      # Vote Abstain
      show_live
      |> element("button#cast-vote-abstain")
      |> render_click()

      assert show_live |> element("button#cast-vote-abstain") |> render() =~ "✓"
      assert show_live |> element("button#cast-vote-abstain") |> render() =~ "Abstain"
    end

    test "loads country vote results only after clicking by country", %{
      conn: conn,
      statement: statement
    } do
      spain = country_fixture(%{name: "Spain"})
      france = country_fixture(%{name: "France"})

      unique = System.unique_integer([:positive])

      user =
        user_fixture(%{}, %{
          name: "Current Voter #{unique}",
          twitter_username: "current_voter_#{unique}",
          bio: "Bio",
          wikipedia_url: "https://en.wikipedia.org/wiki/Current_Voter_#{unique}",
          twin_origin: false,
          country_id: spain.id
        })

      conn = log_in_user(conn, user)

      opinion =
        opinion_fixture(%{
          statement_id: statement.id,
          author_id: user.author_id,
          user_id: user.id,
          source_url: nil,
          twin: false
        })

      spain_author = author_fixture(%{country_id: spain.id})
      france_author = author_fixture(%{country_id: france.id})
      france_quote = opinion_fixture(%{author_id: france_author.id})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: user.author_id,
        opinion_id: opinion.id,
        answer: :for,
        twin: false
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: spain_author.id,
        answer: :abstain
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: france_author.id,
        opinion_id: france_quote.id,
        answer: :against
      })

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert html =~ "Results (3 votes):"
      assert html =~ "Total"
      assert html =~ "For 1 (33%)"
      assert html =~ "Abstain 1 (33%)"
      assert html =~ "Against 1 (33%)"
      assert html =~ "By country"
      refute html =~ "Spain"
      refute html =~ "France"

      html =
        show_live
        |> element("#statement-results-by-country", "By country")
        |> render_click()

      # Opening country results doesn't change the total
      assert html =~ "Results (3 votes):"
      assert html =~ "For 1 (33%)"
      assert html =~ "Abstain 1 (33%)"
      assert html =~ "Against 1 (33%)"
      assert html =~ "Spain"
      assert html =~ "France"

      html =
        show_live
        |> element("input[phx-value-filter='quotes']")
        |> render_click()

      assert html =~ "Results (1 vote):"
      assert html =~ "For 1 (100%)"
      assert html =~ "Against 0 (0%)"
      assert html =~ "Spain"
      refute html =~ "France"
    end

    test "creates a comment", %{conn: conn, statement: statement} do
      conn = log_in_as_user(conn)

      another_user = user_fixture()

      opinion = opinion_fixture(%{statement_id: statement.id})

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{
        twin: true,
        statement_id: statement.id,
        author_id: another_user.author_id,
        opinion_id: opinion.id
      })

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Comment created successfully"
      assert html =~ "some comment"

      # Check that the vote is Abstain
      assert html =~ "Abstain"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "edit a comment", %{conn: conn, statement: statement} do
      user = user_fixture()

      conn = log_in_user(conn, user)

      opinion =
        opinion_fixture(%{
          author_id: user.author_id,
          user_id: user.id,
          statement_id: statement.id,
          content: "whatever",
          twin: false
        })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: user.author_id,
        opinion_id: opinion.id,
        user_id: user.id,
        twin: false
      })

      #  Create an AI generated comment as we don't display the form until we have one of these
      vote_fixture(%{twin: true, statement_id: statement.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert render(show_live) =~ "whatever"

      show_live
      |> element("a", "Edit comment")
      |> render_click()

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      refute html =~ "whatever"
      assert html =~ "some comment"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      statement = statement_fixture()
      vote_fixture(%{statement_id: statement.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # Like the opinion
      show_live
      |> element("img[src='/images/heart.svg']")
      |> render_click()

      # We have a filled heart icon
      assert has_element?(show_live, "img[src='/images/filled-heart.svg']")

      # We don't have a heart icon
      refute has_element?(show_live, "img[src='/images/heart.svg']")

      # Unlike the opinion
      show_live
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      # We have a heart icon
      assert has_element?(show_live, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")
    end

    test "already liked vote opinion renders with filled heart", %{
      conn: conn,
      statement: statement
    } do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      author = author_fixture()
      opinion = opinion_fixture(%{author_id: author.id})

      vote_fixture(%{
        statement_id: statement.id,
        author_id: author.id,
        opinion_id: opinion.id
      })

      {:ok, :liked} = Likes.like(opinion.id, current_user)

      {:ok, show_live, _html} = live(conn, ~p"/p/#{statement.slug}")

      assert has_element?(show_live, "img[src='/images/filled-heart.svg']")
      refute has_element?(show_live, "img[src='/images/heart.svg']")

      show_live
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      assert Likes.count(opinion_id: opinion.id) == 0
      assert has_element?(show_live, "img[src='/images/heart.svg']")
      refute has_element?(show_live, "img[src='/images/filled-heart.svg']")
    end

    test "filters opinions correctly", %{conn: conn, statement: statement} do
      # Create test data
      user = user_fixture()
      ai_author = author_fixture(%{twin: true})
      ai_author_2 = author_fixture(%{twin: true})
      human_author = author_fixture(%{twin: false})

      # Two quote opinions (with source_url) and one user opinion (no source_url)
      _for_quote =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: ai_author.id,
            answer: :for,
            twin: true
          },
          true
        )

      _against_quote =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: ai_author_2.id,
            answer: :against,
            twin: true
          },
          true
        )

      user_opinion = opinion_fixture(%{author_id: human_author.id, source_url: nil, twin: false})

      abstain_opinion =
        opinion_fixture(%{author_id: user.author_id, source_url: nil, twin: false})

      _abstain_user =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: user.author_id,
            answer: :abstain,
            opinion_id: abstain_opinion.id
          },
          false
        )

      _for_user =
        vote_fixture(
          %{
            statement_id: statement.id,
            author_id: human_author.id,
            answer: :for,
            twin: false,
            opinion_id: user_opinion.id
          },
          false
        )

      conn = log_in_user(conn, user)
      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      # Test initial state shows filter buttons
      assert html =~ "Quotes (2)"
      assert html =~ "Users (2)"

      # Default is Quotes filter - should show quote authors, not human authors
      assert html =~ ai_author.name
      refute html =~ human_author.name

      # Test Users filter
      html =
        show_live
        |> element("span", "Users")
        |> render_click()

      assert html =~ human_author.name
      refute html =~ ai_author.name

      # Test switching back to Quotes filter
      html =
        show_live
        |> element("span", "Quotes")
        |> render_click()

      assert html =~ ai_author.name
      refute html =~ human_author.name
    end

    test "shows one card per author and browses older sourced quotes", %{
      conn: conn,
      statement: statement
    } do
      author = author_fixture(%{name: "Multiple Quote Author"})

      newer_quote =
        opinion_fixture(%{
          author_id: author.id,
          content: "Newer sourced quote text",
          source_url: "https://example.com/newer-quote",
          date: ~D[2025-01-01],
          date_precision: :year,
          twin: false
        })

      current_quote =
        opinion_fixture(%{
          author_id: author.id,
          content: "Active older sourced quote text",
          source_url: "https://example.com/older-quote",
          date: ~D[2020-01-01],
          date_precision: :year,
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_quote, statement)
      {:ok, _} = Opinions.add_opinion_to_statement(current_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: current_quote.id,
          answer: :for,
          twin: false
        })

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      # Both quotes appear in the page's JSON-LD; only one is visible in the card
      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()
      assert occurrences(html, ~s(data-testid="vote-card-#{vote.id}")) == 1
      assert card_html =~ "Newer sourced quote text"
      refute card_html =~ "Active older sourced quote text"
      assert html =~ "1 of 2"
      assert html =~ "Quotes (1)"
      assert html =~ "For (1)"

      show_live
      |> element("#vote-component-#{vote.id} button[aria-label='Next quote']")
      |> render_click()

      html = render(show_live)
      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()
      assert occurrences(html, ~s(data-testid="vote-card-#{vote.id}")) == 1
      assert card_html =~ "Active older sourced quote text"
      refute card_html =~ "Newer sourced quote text"
      assert html =~ "2 of 2"
      assert html =~ "Quotes (1)"
      assert html =~ "For (1)"

      show_live
      |> element("#vote-component-#{vote.id} button[aria-label='Previous quote']")
      |> render_click()

      html = render(show_live)
      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()
      assert card_html =~ "Newer sourced quote text"
      refute card_html =~ "Active older sourced quote text"
      assert html =~ "1 of 2"
      assert html =~ "Quotes (1)"
      assert html =~ "For (1)"
    end

    test "keeps delegate opinions first and ranks verified quotes before disputed ones", %{
      conn: conn,
      statement: statement
    } do
      user = user_fixture()

      delegate_author = author_fixture(%{name: "Delegate With Disputed Quote"})
      aggregate_author = author_fixture(%{name: "Aggregate Verified Quote Author"})
      newer_quote_only_author = author_fixture(%{name: "Newer Quote Only Verified Author"})
      older_quote_only_author = author_fixture(%{name: "Older Quote Only Verified Author"})
      disputed_author = author_fixture(%{name: "Disputed Quote Author"})

      delegation_fixture(%{deleguee_id: user.author_id, delegate_id: delegate_author.id})

      delegate_opinion =
        opinion_fixture(%{
          author_id: delegate_author.id,
          content: "Delegate disputed quote",
          verification_status: :disputed
        })

      aggregate_opinion =
        opinion_fixture(%{
          author_id: aggregate_author.id,
          content: "Aggregate verified quote",
          verification_status: :ai_verified,
          likes_count: 0
        })

      newer_quote_only_opinion =
        opinion_fixture(%{
          author_id: newer_quote_only_author.id,
          content: "Newer quote-only verified quote",
          verification_status: :verified,
          likes_count: 0,
          date: ~D[2025-01-01],
          date_precision: :year
        })

      older_quote_only_opinion =
        opinion_fixture(%{
          author_id: older_quote_only_author.id,
          content: "Older high-like quote-only verified quote",
          verification_status: :verified,
          likes_count: 25,
          date: ~D[2020-01-01],
          date_precision: :year
        })

      disputed_opinion =
        opinion_fixture(%{
          author_id: disputed_author.id,
          content: "Newer disputed quote",
          verification_status: :disputed
        })

      for opinion <- [
            delegate_opinion,
            aggregate_opinion,
            newer_quote_only_opinion,
            older_quote_only_opinion,
            disputed_opinion
          ] do
        {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)
      end

      aggregate_opinion.id
      |> YouCongress.OpinionsStatements.get_opinion_statement(statement.id)
      |> Ecto.Changeset.change(verification_status: :ai_verified)
      |> YouCongress.Repo.update!()

      vote_fixture(%{
        statement_id: statement.id,
        author_id: delegate_author.id,
        opinion_id: delegate_opinion.id,
        answer: :for
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: aggregate_author.id,
        opinion_id: aggregate_opinion.id,
        answer: :for,
        verification_status: :ai_verified
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: newer_quote_only_author.id,
        opinion_id: newer_quote_only_opinion.id,
        answer: :for
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: older_quote_only_author.id,
        opinion_id: older_quote_only_opinion.id,
        answer: :for
      })

      vote_fixture(%{
        statement_id: statement.id,
        author_id: disputed_author.id,
        opinion_id: disputed_opinion.id,
        answer: :for
      })

      conn = log_in_user(conn, user)
      {:ok, _show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      assert [
               delegate_position,
               aggregate_position,
               newer_quote_only_position,
               older_quote_only_position,
               disputed_position
             ] =
               Enum.map(
                 [
                   "Delegate disputed quote",
                   "Aggregate verified quote",
                   "Newer quote-only verified quote",
                   "Older high-like quote-only verified quote",
                   "Newer disputed quote"
                 ],
                 fn quote ->
                   case :binary.match(html, quote) do
                     {position, _length} -> position
                     :nomatch -> flunk("Expected #{quote} in statement page")
                   end
                 end
               )

      assert delegate_position < aggregate_position
      assert aggregate_position < newer_quote_only_position
      assert newer_quote_only_position < older_quote_only_position
      assert older_quote_only_position < disputed_position
    end

    test "ranks an author's verified alternate quote before a newer disputed quote", %{
      conn: conn,
      statement: statement
    } do
      author = author_fixture(%{name: "Alternate Quote Author"})

      disputed_quote =
        opinion_fixture(%{
          author_id: author.id,
          content: "Newer disputed alternate quote",
          source_url: "https://example.com/disputed-alternate",
          date: ~D[2025-01-01],
          date_precision: :year,
          verification_status: :disputed,
          twin: false
        })

      verified_quote =
        opinion_fixture(%{
          author_id: author.id,
          content: "Older verified alternate quote",
          source_url: "https://example.com/verified-alternate",
          date: ~D[2020-01-01],
          date_precision: :year,
          verification_status: :ai_verified,
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(disputed_quote, statement.id)
      {:ok, _} = Opinions.add_opinion_to_statement(verified_quote, statement.id)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: verified_quote.id,
          answer: :for,
          twin: false
        })

      {:ok, show_live, html} = live(conn, ~p"/p/#{statement.slug}")

      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()
      assert card_html =~ "Older verified alternate quote"
      refute card_html =~ "Newer disputed alternate quote"
      assert html =~ "1 of 2"

      show_live
      |> element("#vote-component-#{vote.id} button[aria-label='Next quote']")
      |> render_click()

      card_html = show_live |> element("#vote-component-#{vote.id}") |> render()
      assert card_html =~ "Newer disputed alternate quote"
      refute card_html =~ "Older verified alternate quote"
    end
  end
end
