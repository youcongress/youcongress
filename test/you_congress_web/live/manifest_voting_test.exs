defmodule YouCongressWeb.ManifestVotingTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.Votes

  describe "Manifest Voting" do
    test "user can vote on motion from manifest page", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      voting = voting_fixture(title: "AI Safety")
      manifest = manifest_fixture()
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting.id, body: "Paragraph 1"})

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}")

      assert has_element?(view, "h3", "AI Safety")

      # Vote Against
      view
      |> element("button", "Against")
      |> render_click()

      # Verify vote recorded
      vote = Votes.get_current_user_vote(voting.id, user.author_id)
      assert vote.answer == :against

      # Verify UI update (button active state)
      assert has_element?(view, "button.bg-red-100", "Against")

      # Vote For
      view
      |> element("button", "For")
      |> render_click()

      vote = Votes.get_current_user_vote(voting.id, user.author_id)
      assert vote.answer == :for
       assert has_element?(view, "button.bg-green-100", "For")
    end

    test "user can clear their vote", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      voting = voting_fixture(title: "Clear Vote Test")
      manifest = manifest_fixture()
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting.id, body: "Paragraph 1"})

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}")

      # Vote For
      view
      |> element("button", "For")
      |> render_click()

      assert has_element?(view, "button.bg-green-100", "For")

      # Clear vote
      view
      |> element("button", "clear")
      |> render_click()

      # Verify vote removed
      refute has_element?(view, "button.bg-green-100", "For")
      # Verify clear button is gone
      refute has_element?(view, "button", "clear")

      assert Votes.get_current_user_vote(voting.id, user.author_id) == nil
    end

    test "displays vote counts", %{conn: conn} do
      user = user_fixture()
      voting = voting_fixture()
      manifest = manifest_fixture()
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting.id})

      # Create some initial votes
      Votes.create_vote(%{voting_id: voting.id, author_id: user.author_id, answer: :for, direct: true})

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}")

      # Check if results component is rendered (it renders percentages/bars)
      assert render(view) =~ "Results"
    end
  end
end
