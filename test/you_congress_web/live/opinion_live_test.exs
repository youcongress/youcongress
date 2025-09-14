defmodule YouCongressWeb.OpinionLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotingsFixtures

  alias YouCongress.Opinions

  describe "Index" do
    test "comment under a comment", %{conn: conn} do
      conn = log_in_as_user(conn)
      author1 = author_fixture(%{name: "Someone1"})
      voting = voting_fixture(%{author_id: author1.id})

      opinion =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          voting_id: voting.id,
          twin: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      index_live
      |> form("form", opinion: %{content: "Opinion2"})
      |> render_submit()

      assert Opinions.list_opinions() |> Enum.map(& &1.content) |> Enum.sort() == [
               "Opinion1",
               "Opinion2"
             ]
    end
  end
end
