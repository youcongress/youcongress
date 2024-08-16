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
             |> render_submit() =~ "Quote added"

      [vote] = Votes.list_votes()

      assert vote.voting_id == voting.id
      assert vote.answer_id == Answers.get_answer_id("Strongly agree")

      # Verify the quote has been added to the database
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

      html = render(add_quote_live)

      assert html =~ "Quote added."

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
      add_quote_live
      |> form("form",
        opinion: "Democracy is essential 2.",
        source_url: "http://example.com/democracy_quote2",
        agree_rate: "Strongly disagree"
      )
      |> render_submit()

      html = render(add_quote_live)

      assert html =~ "Quote added."

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

      author = Authors.get_author_by_twitter_username("someone")
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

      html = render(add_quote_live)

      assert html =~ "Quote added."

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
  end
end
