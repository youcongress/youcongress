defmodule YouCongressWeb.VoteLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.VotesFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures

  @update_attrs %{opinion: "some updated opinion"}
  @invalid_attrs %{opinion: nil}

  defp create_vote(_) do
    vote = vote_fixture()
    %{vote: vote}
  end

  describe "Index" do
    setup [:create_vote]

    test "lists all votes", %{conn: conn, vote: vote} do
      {:ok, _index_live, html} = live(conn, ~p"/votes")

      assert html =~ "Listing Votes"
      assert html =~ vote.opinion
    end

    #  We skip it until we add the selects for author and voting
    @tag :skip
    test "saves new vote", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/votes")

      assert index_live |> element("a", "New Vote") |> render_click() =~
               "New Vote"

      assert_patch(index_live, ~p"/votes/new")

      assert index_live
             |> form("#vote-form", vote: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      create_attrs = %{
        opinion: "some opinion",
        author_id: author_fixture().id,
        voting_id: voting_fixture().id
      }

      assert index_live
             |> form("#vote-form", vote: create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/votes")

      html = render(index_live)
      assert html =~ "Vote created successfully"
      assert html =~ "some opinion"
    end

    test "updates vote in listing", %{conn: conn, vote: vote} do
      {:ok, index_live, _html} = live(conn, ~p"/votes")

      assert index_live |> element("#votes-#{vote.id} a", "Edit") |> render_click() =~
               "Edit Vote"

      assert_patch(index_live, ~p"/votes/#{vote}/edit")

      assert index_live
             |> form("#vote-form", vote: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#vote-form", vote: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/votes")

      html = render(index_live)
      assert html =~ "Vote updated successfully"
      assert html =~ "some updated opinion"
    end

    test "deletes vote in listing", %{conn: conn, vote: vote} do
      {:ok, index_live, _html} = live(conn, ~p"/votes")

      assert index_live |> element("#votes-#{vote.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#votes-#{vote.id}")
    end
  end

  describe "Show" do
    setup [:create_vote]

    test "displays vote", %{conn: conn, vote: vote} do
      {:ok, _show_live, html} = live(conn, ~p"/votes/#{vote}")

      assert html =~ "Show Vote"
      assert html =~ vote.opinion
    end

    test "updates vote within modal", %{conn: conn, vote: vote} do
      {:ok, show_live, _html} = live(conn, ~p"/votes/#{vote}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Vote"

      assert_patch(show_live, ~p"/votes/#{vote}/show/edit")

      assert show_live
             |> form("#vote-form", vote: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#vote-form", vote: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/votes/#{vote}")

      html = render(show_live)
      assert html =~ "Vote updated successfully"
      assert html =~ "some updated opinion"
    end
  end
end
