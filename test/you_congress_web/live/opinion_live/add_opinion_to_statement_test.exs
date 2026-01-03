defmodule YouCongressWeb.OpinionLive.AddOpinionToStatementTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Votes

  describe "Show - Add to Statement" do
    test "search for voting and add opinion with vote", %{conn: conn} do
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
      |> element("button", "Add to Poll")
      |> render_click()

      # Search for voting
      show_live
      |> form("form[phx-submit='search-statements']", %{value: "Relevant"})
      |> render_submit()

      # Select voting
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
  end
end
