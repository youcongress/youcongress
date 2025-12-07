defmodule YouCongressWeb.OpinionLive.AddOpinionToVotingTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.AccountsFixtures

  alias YouCongress.Votes

  describe "Show - Add to Voting" do
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

      voting = voting_fixture(%{title: "Relevant Poll Title"})

      {:ok, show_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      # Toggle search
      show_live
      |> element("button", "Add to Poll")
      |> render_click()

      # Search for voting
      show_live
      |> form("form[phx-submit='search-votings']", %{value: "Relevant"})
      |> render_submit()

      # Select voting
      show_live
      |> element("button[phx-click='show-vote-options'][phx-value-voting_id='#{voting.id}']")
      |> render_click()

      # Check for new options
      assert has_element?(show_live, "button", "For")
      assert has_element?(show_live, "button", "Against")
      assert has_element?(show_live, "button", "Abstain")
      refute has_element?(show_live, "button", "Strongly Agree")

      # Vote For
      show_live
      |> element("button[phx-click='add-to-voting-with-vote'][phx-value-answer='For']")
      |> render_click()

      assert render(show_live) =~ "Opinion added to voting with your vote (For) successfully"

      # Verify vote created
      [vote] = Votes.list_votes(author_ids: [author.id], voting_ids: [voting.id])
      assert vote.answer == :for
      assert vote.opinion_id == opinion.id
    end
  end
end
