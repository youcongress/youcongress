defmodule YouCongressWeb.OpinionLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.OpinionsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures

  @update_attrs %{opinion: "some updated opinion"}
  @invalid_attrs %{opinion: nil}

  defp create_opinion(_) do
    opinion = opinion_fixture()
    %{opinion: opinion}
  end

  describe "Index" do
    setup [:create_opinion]

    test "lists all opinions", %{conn: conn, opinion: opinion} do
      {:ok, _index_live, html} = live(conn, ~p"/opinions")

      assert html =~ "Listing Opinions"
      assert html =~ opinion.opinion
    end

    #  We skip it until we add the selects for author and voting
    @tag :skip
    test "saves new opinion", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/opinions")

      assert index_live |> element("a", "New Opinion") |> render_click() =~
               "New Opinion"

      assert_patch(index_live, ~p"/opinions/new")

      assert index_live
             |> form("#opinion-form", opinion: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      create_attrs = %{
        opinion: "some opinion",
        author_id: author_fixture().id,
        voting_id: voting_fixture().id
      }

      assert index_live
             |> form("#opinion-form", opinion: create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/opinions")

      html = render(index_live)
      assert html =~ "Opinion created successfully"
      assert html =~ "some opinion"
    end

    test "updates opinion in listing", %{conn: conn, opinion: opinion} do
      {:ok, index_live, _html} = live(conn, ~p"/opinions")

      assert index_live |> element("#opinions-#{opinion.id} a", "Edit") |> render_click() =~
               "Edit Opinion"

      assert_patch(index_live, ~p"/opinions/#{opinion}/edit")

      assert index_live
             |> form("#opinion-form", opinion: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#opinion-form", opinion: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/opinions")

      html = render(index_live)
      assert html =~ "Opinion updated successfully"
      assert html =~ "some updated opinion"
    end

    test "deletes opinion in listing", %{conn: conn, opinion: opinion} do
      {:ok, index_live, _html} = live(conn, ~p"/opinions")

      assert index_live |> element("#opinions-#{opinion.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#opinions-#{opinion.id}")
    end
  end

  describe "Show" do
    setup [:create_opinion]

    test "displays opinion", %{conn: conn, opinion: opinion} do
      {:ok, _show_live, html} = live(conn, ~p"/opinions/#{opinion}")

      assert html =~ "Show Opinion"
      assert html =~ opinion.opinion
    end

    test "updates opinion within modal", %{conn: conn, opinion: opinion} do
      {:ok, show_live, _html} = live(conn, ~p"/opinions/#{opinion}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Opinion"

      assert_patch(show_live, ~p"/opinions/#{opinion}/show/edit")

      assert show_live
             |> form("#opinion-form", opinion: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#opinion-form", opinion: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/opinions/#{opinion}")

      html = render(show_live)
      assert html =~ "Opinion updated successfully"
      assert html =~ "some updated opinion"
    end
  end
end
