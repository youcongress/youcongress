defmodule YouCongressWeb.OpinionLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotingsFixtures

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion

  describe "Index" do
    test "comment under a comment from a real person", %{conn: conn} do
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

    test "comment under a comment from a digital twin and the twin replies", %{conn: conn} do
      conn = log_in_as_user(conn)
      author1 = author_fixture(%{name: "Someone1"})

      opinion =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          twin: true
        })

      {:ok, index_live, _html} = live(conn, ~p"/c/#{opinion.id}")

      index_live
      |> form("form", opinion: %{content: "Opinion2"})
      |> render_submit()

      #  The previous two opinions plus the twin reply
      assert length(Opinions.list_opinions()) == 3

      opinion = Opinions.get_by(content: "Opinion2")
      [new_twin_comment] = Opinion.descendants(opinion)
      assert new_twin_comment.twin
    end
  end
end
