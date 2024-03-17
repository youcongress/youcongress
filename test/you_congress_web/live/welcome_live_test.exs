defmodule YouCongressWeb.WelcomeLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  defp create_user(_) do
    current_user = user_fixture(%{}, %{name: "Someone"})
    %{current_user: current_user}
  end

  describe "Welcome" do
    setup [:create_user]

    test "Non-logged visitors can't load the page", %{conn: conn} do
      {:error,
       {:redirect, %{flash: %{"error" => "You must log in to access this page."}, to: "/"}}} =
        live(conn, ~p"/welcome")
    end

    test "Logged users can load the page", %{conn: conn, current_user: current_user} do
      conn = log_in_user(conn, current_user)
      {:ok, _welcome_live, html} = live(conn, ~p"/welcome")
      assert html =~ "Welcome to YouCongress"
    end

    test "Accepting the newsletter, saves it and redirects to home", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, welcome_live, _html} = live(conn, ~p"/welcome")

      assert current_user.newsletter == false

      {:error, {:redirect, %{to: "/home"}}} =
        welcome_live
        |> form("#user-form", %{"user[newsletter]" => true})
        |> render_submit()

      current_user = Accounts.get_user!(current_user.id)

      assert current_user.newsletter == true
    end

    test "Not accepting the newsletter, saves it and redirects to home", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, welcome_live, _html} = live(conn, ~p"/welcome")

      assert current_user.newsletter == false

      {:error, {:redirect, %{to: "/home"}}} =
        welcome_live
        |> form("#user-form", %{"user[newsletter]" => false})
        |> render_submit()

      current_user = Accounts.get_user!(current_user.id)

      assert current_user.newsletter == false
    end
  end
end
