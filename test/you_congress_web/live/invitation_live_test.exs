defmodule YouCongressWeb.InvitationLiveTest do
  use YouCongressWeb.ConnCase

  alias YouCongress.Invitations

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  describe "Invitations page" do
    test "renders invitations page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(admin_fixture())
        |> live(~p"/i")

      assert html =~ "Invite a friend"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/i")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/log_in"
      assert %{"error" => "You must be an admin to access this page."} = flash
    end

    test "redirects if user is not an admin", %{conn: conn} do
      user = user_fixture()
      assert {:error, redirect} = live(log_in_user(conn, user), ~p"/i")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/log_in"
      assert %{"error" => "You must be an admin to access this page."} = flash
    end
  end

  describe "Invite a friend" do
    setup %{conn: conn} do
      user = admin_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "invites a friend", %{conn: conn, user: _user} do
      new_twitter_username = "whatever"

      {:ok, lv, _html} = live(conn, ~p"/i")

      result =
        lv
        |> form("#invite_form", %{
          "invitation[twitter_username]" => new_twitter_username
        })
        |> render_submit()

      assert result =~ "@#{new_twitter_username} has been invited"

      assert Invitations.list_invitations() |> Enum.map(& &1.twitter_username) == [
               new_twitter_username
             ]
    end
  end
end
