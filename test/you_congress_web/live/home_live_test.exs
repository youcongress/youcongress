defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotingsFixtures

  describe "Index" do
    test "lists recent root opinions", %{conn: conn} do
      author1 = author_fixture(%{name: "Someone1"})

      voting = voting_fixture(%{author_id: author1.id})

      opinion1 =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          voting_id: voting.id,
          twin: false
        })

      author2 = author_fixture(%{name: "Someone2"})

      opinion2 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion2",
          voting_id: voting.id,
          twin: false
        })

      opinion3 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion3",
          voting_id: voting.id,
          ancestry: "#{opinion2.id}",
          twin: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/")

      html = render(index_live)

      assert html =~ opinion1.content
      assert html =~ opinion2.content
      assert html =~ author1.name
      assert html =~ author2.name

      # Does not include opinion3
      refute html =~ opinion3.content
    end

    test "lists all recent opinions", %{conn: conn} do
      author1 = author_fixture(%{name: "Someone1"})

      voting = voting_fixture(%{author_id: author1.id})

      opinion1 =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          voting_id: voting.id,
          twin: false
        })

      author2 = author_fixture(%{name: "Someone2"})

      opinion2 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion2",
          voting_id: voting.id,
          twin: false
        })

      opinion3 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion3",
          voting_id: voting.id,
          ancestry: "#{opinion2.id}",
          twin: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/?all=true")

      html = render(index_live)

      assert html =~ opinion1.content
      assert html =~ opinion2.content
      assert html =~ opinion3.content
      assert html =~ author1.name
      assert html =~ author2.name
    end
  end
end
