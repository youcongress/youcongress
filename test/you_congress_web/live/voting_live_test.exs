defmodule YouCongressWeb.VotingLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.VotingsFixtures

  @create_attrs %{title: "some nice title"}
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_voting(_) do
    voting = voting_fixture()
    %{voting: voting}
  end

  describe "Index" do
    setup [:create_voting]

    test "lists all votings", %{conn: conn, voting: voting} do
      {:ok, _index_live, html} = live(conn, ~p"/votings")

      assert html =~ "Listing Votings"
      assert html =~ voting.title
    end

    test "saves new voting", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/votings")

      assert index_live |> element("a", "New Voting") |> render_click() =~
               "New Voting"

      assert_patch(index_live, ~p"/votings/new")

      assert index_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#voting-form", voting: @create_attrs)
             |> render_submit()

      # assert_patch(index_live, ~p"/votings")

      html = render(index_live)
      assert html =~ "Voting created successfully"
      assert html =~ "some title"
    end

    test "updates voting in listing", %{conn: conn, voting: voting} do
      {:ok, index_live, _html} = live(conn, ~p"/votings")

      assert index_live |> element("#votings-#{voting.id} a", "Edit") |> render_click() =~
               "Edit Voting"

      assert_patch(index_live, ~p"/votings/#{voting}/edit")

      assert index_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#voting-form", voting: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/votings")

      html = render(index_live)
      assert html =~ "Voting updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes voting in listing", %{conn: conn, voting: voting} do
      {:ok, index_live, _html} = live(conn, ~p"/votings")

      assert index_live |> element("#votings-#{voting.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#votings-#{voting.id}")
    end
  end

  describe "Show" do
    setup [:create_voting]

    test "displays voting", %{conn: conn, voting: voting} do
      {:ok, _show_live, html} = live(conn, ~p"/votings/#{voting}")

      assert html =~ "Show Voting"
      assert html =~ voting.title
    end

    test "updates voting within modal", %{conn: conn, voting: voting} do
      {:ok, show_live, _html} = live(conn, ~p"/votings/#{voting}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Voting"

      assert_patch(show_live, ~p"/votings/#{voting}/show/edit")

      assert show_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#voting-form", voting: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/votings/#{voting}")

      html = render(show_live)
      assert html =~ "Voting updated successfully"
      assert html =~ "some updated title"
    end
  end
end
