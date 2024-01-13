defmodule YouCongressWeb.VotingLiveTest do
  use YouCongressWeb.ConnCase

  import Mock

  import Phoenix.LiveViewTest
  import YouCongress.VotingsFixtures

  alias YouCongress.Votings

  @create_attrs %{title: "nuclear energy"}
  @suggested_titles [
    "Should we increase investment in nuclear energy research?",
    "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    "Could nuclear energy be a key solution for reducing global carbon emissions?"
  ]
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_voting(_) do
    voting = voting_fixture()
    %{voting: voting}
  end

  describe "Index" do
    setup [:create_voting]

    test "lists all votings", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)
      {:ok, _index_live, html} = live(conn, ~p"/home")

      assert html =~ "Votings"
      assert html =~ voting.title
    end

    test "saves new voting and redirect to show", %{conn: conn} do
      with_mocks([
        {YouCongress.Votings.TitleRewording, [],
         [generate_rewordings: fn _, _ -> {:ok, @suggested_titles, 0} end]},
        {Oban, [], [insert: fn _ -> {:ok, %{id: 1}} end]}
      ]) do
        conn = log_in_as_admin(conn)
        {:ok, index_live, _html} = live(conn, ~p"/home")

        assert index_live
               |> form("#voting-form", voting: @invalid_attrs)
               |> render_change() =~ "can&#39;t be blank"

        [title1, title2, _title3] = @suggested_titles

        assert index_live
               |> form("#voting-form", voting: @create_attrs)
               |> render_submit() =~ title1

        response =
          index_live
          |> element("button", title2)
          |> render_click()

        voting = Votings.get_voting!(%{title: title2})
        voting_path = ~p"/v/#{voting.id}"

        {_, {:redirect, %{to: ^voting_path}}} = response
      end
    end
  end

  describe "Show" do
    setup [:create_voting]

    test "displays voting", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      {:ok, _show_live, html} = live(conn, ~p"/v/#{voting}")

      assert html =~ "Show Voting"
      assert html =~ voting.title
    end

    test "updates voting within modal", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, show_live, _html} = live(conn, ~p"/v/#{voting}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Voting"

      assert_patch(show_live, ~p"/v/#{voting}/show/edit")

      assert show_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#voting-form", voting: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/v/#{voting}")

      html = render(show_live)
      assert html =~ "Voting updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes voting in listing", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/v/#{voting.id}/edit")

      index_live
      |> element("a", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Votings.get_voting!(voting.id)
      end
    end
  end
end
