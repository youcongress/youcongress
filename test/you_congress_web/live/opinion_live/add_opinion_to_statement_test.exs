defmodule YouCongressWeb.OpinionLive.AddOpinionToStatementTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Votes
  alias YouCongress.Opinions

  describe "Show - Add to Statement" do
    test "search for statement and add opinion with vote", %{conn: conn} do
      user = user_fixture()
      author = author_fixture(%{user_id: user.id, name: "Opinion Author"})
      conn = log_in_as_admin(conn)

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: user.id,
          content: "Quote content",
          twin: false,
          source_url: "https://example.com"
        })

      statement = statement_fixture(%{title: "Relevant Poll Title"})

      {:ok, show_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      # Toggle search
      show_live
      |> element("button", "Add to Statement")
      |> render_click()

      # Search for statement
      show_live
      |> form("form[phx-submit='search-statements']", %{value: "Relevant"})
      |> render_submit()

      # Select statement
      show_live
      |> element(
        "button[phx-click='show-vote-options'][phx-value-statement_id='#{statement.id}']"
      )
      |> render_click()

      # Check for new options
      assert has_element?(show_live, "button", "For")
      assert has_element?(show_live, "button", "Against")
      assert has_element?(show_live, "button", "Abstain")
      refute has_element?(show_live, "button", "Strongly Agree")

      # Vote For
      show_live
      |> element("button[phx-click='add-to-statement-with-vote'][phx-value-answer='For']")
      |> render_click()

      assert render(show_live) =~ "Opinion added to statement with your vote (For) successfully"

      # Verify vote created
      [vote] = Votes.list_votes(author_ids: [author.id], statement_ids: [statement.id])
      assert vote.answer == :for
      assert vote.opinion_id == opinion.id
    end

    test "regular users cannot manually add an opinion to a statement", %{conn: conn} do
      owner = user_fixture()
      author = author_fixture(%{user_id: owner.id, name: "Opinion Author"})
      regular_user = user_fixture()
      conn = log_in_user(conn, regular_user)

      opinion =
        opinion_fixture(%{
          author_id: author.id,
          user_id: owner.id,
          content: "Quote content",
          twin: false,
          source_url: "https://example.com"
        })

      statement = statement_fixture(%{title: "Relevant Poll Title"})

      {:ok, show_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      html =
        render_click(show_live, "add-to-statement", %{
          "statement_id" => "#{statement.id}"
        })

      assert html =~ "You don&#39;t have permission to do this."

      reloaded_opinion = Opinions.get_opinion!(opinion.id, preload: [:statements])
      refute Enum.any?(reloaded_opinion.statements, &(&1.id == statement.id))
      assert [] == Votes.list_votes(author_ids: [author.id], statement_ids: [statement.id])
    end
  end
end
