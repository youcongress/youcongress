defmodule YouCongressWeb.VoteLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.VotesFixtures

  defp create_vote(_) do
    vote = vote_fixture()
    %{vote: vote}
  end

  describe "Index" do
    setup [:create_vote]

    test "lists all votes", %{conn: conn, vote: vote} do
      conn = log_in_as_user(conn)
      {:ok, _index_live, html} = live(conn, ~p"/votes")

      assert html =~ "Listing Votes"
      assert html =~ vote.opinion
    end
  end
end
