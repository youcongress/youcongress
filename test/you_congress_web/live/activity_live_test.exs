defmodule YouCongressWeb.ActivityLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.AccountsFixtures

  describe "Index" do
    test "lists recent opinions", %{conn: conn} do
      author1 = author_fixture(%{name: "Someone1"})

      voting = voting_fixture(%{author_id: author1.id})

      opinion1 =
        opinion_fixture(%{
          author_id: author1.id,
          content: "Opinion1",
          voting_id: voting.id,
          twin: true
        })

      author2 = author_fixture(%{name: "Someone2"})

      opinion2 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion2",
          voting_id: voting.id,
          twin: true
        })

      opinion3 =
        opinion_fixture(%{
          author_id: author2.id,
          content: "Opinion3",
          voting_id: voting.id,
          ancestry: "#{opinion2.id}",
          twin: false
        })

      {:ok, index_live, _html} = live(conn, ~p"/home")

      # Toggle switch to include AI twins so we can see all opinions
      index_live
      |> element("button[phx-click='toggle-switch']")
      |> render_click()

      html = render(index_live)

      assert html =~ opinion1.content
      assert html =~ opinion2.content
      assert html =~ author1.name
      assert html =~ author2.name
      assert html =~ opinion3.content
    end

    test "like icon click changes from heart.svg to filled-heart.svg", %{conn: conn} do
      current_user = user_fixture()
      conn = log_in_user(conn, current_user)
      voting = voting_fixture()
      opinion_fixture(%{voting_id: voting.id, twin: false})

      {:ok, view, _html} = live(conn, "/home")

      # We have a heart icon
      assert has_element?(view, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(view, "img[src='/images/filled-heart.svg']")

      # Like the opinion
      view
      |> element("img[src='/images/heart.svg']")
      |> render_click()

      # We have a filled heart icon
      assert has_element?(view, "img[src='/images/filled-heart.svg']")

      # We don't have a heart icon
      refute has_element?(view, "img[src='/images/heart.svg']")

      # Unlike the opinion
      view
      |> element("img[src='/images/filled-heart.svg']")
      |> render_click()

      # We have a heart icon
      assert has_element?(view, "img[src='/images/heart.svg']")

      # We don't have a filled heart icon
      refute has_element?(view, "img[src='/images/filled-heart.svg']")
    end
  end
end
