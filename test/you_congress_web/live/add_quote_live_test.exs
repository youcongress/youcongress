defmodule YouCongressWeb.AddQuoteLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Authors
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers
  alias YouCongress.Opinions

  defp create_voting(_) do
    voting = voting_fixture()
    %{voting: voting}
  end

  describe "Add quote" do
    setup [:create_voting]

    test "adds a quote with twitter username in URL", %{conn: conn, voting: voting} do
      author = author_fixture(%{twitter_username: "someone"})
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      assert html =~ "Add a quote"

      assert add_quote_live
             |> form("form",
               opinion: "Democracy is essential.",
               source_url: "http://example.com/democracy_quote",
               agree_rate: "Strongly agree"
             )
             |> render_submit()

      # Assert redirect
      assert_redirected(add_quote_live, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id
      assert opinion.content == "Democracy is essential."
      assert opinion.source_url == "http://example.com/democracy_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end

    test "adds a quote without passing username as a param", %{conn: conn, voting: voting} do
      author = author_fixture(%{twitter_username: "someone"})
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote")

      assert html =~ "Add a quote"

      assert add_quote_live
             |> form("form",
               twitter_username: "someone"
             )
             |> render_submit()

      #  Now we can add the quote

      add_quote_live
      |> form("form",
        opinion: "Democracy is essential.",
        source_url: "http://example.com/democracy_quote",
        agree_rate: "Strongly agree"
      )
      |> render_submit()

      # Assert redirect
      assert_redirected(add_quote_live, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id
      assert opinion.content == "Democracy is essential."
      assert opinion.source_url == "http://example.com/democracy_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false

      assert vote.opinion_id == opinion.id

      # Now we add another quote (the flow is different when an author already has a quote on a voting)
      {:ok, add_quote_live, _html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      add_quote_live
      |> form("form",
        opinion: "Democracy is essential 2.",
        source_url: "http://example.com/democracy_quote2",
        agree_rate: "Strongly disagree"
      )
      |> render_submit()

      assert_redirected(add_quote_live, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly disagree")

      opinion = Opinions.get_opinion!(vote.opinion_id)
      assert opinion.author_id == author.id
      assert opinion.content == "Democracy is essential 2."
      assert opinion.source_url == "http://example.com/democracy_quote2"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end

    test "creates an author and adds a quote", %{conn: conn, voting: voting} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote")

      assert html =~ "Add a quote"

      assert add_quote_live
             |> form("form",
               twitter_username: "someone"
             )
             |> render_submit()

      html = render(add_quote_live)

      # Verify that
      assert html =~ "Author not found. Please fill the form."
      refute html =~ "Source URL"

      add_quote_live
      |> form("form",
        name: "Someone",
        bio: "Someone bio",
        wikipedia_url: "http://example.com/someone"
      )
      |> render_submit()

      html = render(add_quote_live)

      assert html =~ "Author created."

      author = Authors.get_author_by(twitter_username: "someone")
      assert author.name == "Someone"
      assert author.bio == "Someone bio"
      assert author.wikipedia_url == "http://example.com/someone"

      add_quote_live
      |> form("form",
        opinion: "Democracy is essential.",
        source_url: "http://example.com/democracy_quote",
        agree_rate: "Strongly agree"
      )
      |> render_submit()

      assert_redirected(add_quote_live, ~p"/p/#{voting.slug}/add-quote?twitter_username=someone")

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id
      assert opinion.content == "Democracy is essential."
      assert opinion.source_url == "http://example.com/democracy_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end

    test "adds a quote with wikipedia URL in URL", %{conn: conn, voting: voting} do
      author =
        author_fixture(%{
          name: "Albert Einstein",
          bio: "Theoretical physicist",
          wikipedia_url: "https://en.wikipedia.org/wiki/Albert_Einstein",
          twitter_username: nil
        })

      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}")

      assert html =~ "Add a quote"
      assert html =~ "Albert Einstein"
      assert html =~ "Wikipedia"

      assert add_quote_live
             |> form("form",
               opinion: "Imagination is more important than knowledge.",
               source_url: "http://example.com/einstein_quote",
               agree_rate: "Strongly agree"
             )
             |> render_submit()

      # Assert redirect
      assert_redirected(
        add_quote_live,
        ~p"/p/#{voting.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}"
      )

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id
      assert opinion.content == "Imagination is more important than knowledge."
      assert opinion.source_url == "http://example.com/einstein_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end

    test "finds author by wikipedia URL without param", %{conn: conn, voting: voting} do
      author =
        author_fixture(%{
          name: "Albert Einstein",
          bio: "Theoretical physicist",
          wikipedia_url: "https://en.wikipedia.org/wiki/Albert_Einstein",
          twitter_username: nil
        })

      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote")

      assert html =~ "Add a quote"

      assert add_quote_live
             |> form("form",
               wikipedia_url: "https://en.wikipedia.org/wiki/Albert_Einstein"
             )
             |> render_submit()

      # Should find the author and show the quote form
      html = render(add_quote_live)
      assert html =~ "Albert Einstein"
      assert html =~ "Wikipedia"

      add_quote_live
      |> form("form",
        opinion: "Imagination is more important than knowledge.",
        source_url: "http://example.com/einstein_quote",
        agree_rate: "Strongly agree"
      )
      |> render_submit()

      # Assert redirect
      assert_redirected(
        add_quote_live,
        ~p"/p/#{voting.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}"
      )

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id
      assert opinion.content == "Imagination is more important than knowledge."
      assert opinion.source_url == "http://example.com/einstein_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end

    test "creates an author with wikipedia URL only", %{conn: conn, voting: voting} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)

      {:ok, add_quote_live, html} =
        live(conn, ~p"/p/#{voting.slug}/add-quote")

      assert html =~ "Add a quote"

      assert add_quote_live
             |> form("form",
               wikipedia_url: "https://en.wikipedia.org/wiki/Isaac_Newton"
             )
             |> render_submit()

      html = render(add_quote_live)
      assert html =~ "Author not found. Please fill the form."

      add_quote_live
      |> form("form",
        name: "Isaac Newton",
        bio: "English mathematician and physicist"
      )
      |> render_submit()

      html = render(add_quote_live)
      assert html =~ "Author created."

      author = Authors.get_author_by(wikipedia_url: "https://en.wikipedia.org/wiki/Isaac_Newton")
      assert author.name == "Isaac Newton"
      assert author.bio == "English mathematician and physicist"
      assert author.wikipedia_url == "https://en.wikipedia.org/wiki/Isaac_Newton"
      assert author.twitter_username == nil

      add_quote_live
      |> form("form",
        opinion: "If I have seen further it is by standing on the shoulders of Giants.",
        source_url: "http://example.com/newton_quote",
        agree_rate: "Strongly agree"
      )
      |> render_submit()

      assert_redirected(
        add_quote_live,
        ~p"/p/#{voting.slug}/add-quote?wikipedia_url=#{author.wikipedia_url}"
      )

      # Verify the data was saved
      [vote] = Votes.list_votes()
      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      [opinion] = Opinions.list_opinions()
      assert opinion.author_id == author.id

      assert opinion.content ==
               "If I have seen further it is by standing on the shoulders of Giants."

      assert opinion.source_url == "http://example.com/newton_quote"
      assert opinion.user_id == current_user.id
      assert opinion.twin == false
    end
  end
end
