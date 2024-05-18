defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.OpinionsFixtures

  describe "Index" do
    test "lists recent votes and opinions", %{conn: conn} do
      author1 = author_fixture(%{name: "Someone1"})
      opinion1 = opinion_fixture(%{author_id: author1.id, content: "Opinion1"})
      vote_fixture(%{author_id: author1.id, opinion_id: opinion1.id})

      author2 = author_fixture(%{name: "Someone2"})
      opinion2 = opinion_fixture(%{author_id: author2.id, content: "Opinion2"})
      vote_fixture(%{author_id: author2.id, opinion_id: opinion2.id})

      conn = log_in_as_admin(conn)

      {:ok, _index_live, html} = live(conn, ~p"/home")

      assert html =~ "Recent activity"
      assert html =~ opinion1.content
      assert html =~ opinion2.content
      assert html =~ author1.name
      assert html =~ author2.name
    end
  end
end
