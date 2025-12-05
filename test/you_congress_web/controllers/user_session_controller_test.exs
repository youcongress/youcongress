defmodule YouCongressWeb.UserSessionControllerTest do
  use YouCongressWeb.ConnCase, async: true

  alias YouCongress.Repo
  import YouCongress.AccountsFixtures
  import Ecto.Changeset

  setup do
    %{user: user_fixture()}
  end

  describe "POST /log_in" do
    test "prevents login for user with spam role", %{conn: conn, user: user} do
      {:ok, blocked_user} =
        user
        |> change(role: "spam")
        |> Repo.update()

      conn =
        conn
        |> post(~p"/log_in", %{
          "user" => %{"email" => blocked_user.email, "password" => "hello world!"}
        })
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
    end

    test "prevents login for user with blocked role", %{conn: conn, user: user} do
      {:ok, blocked_user} =
        user
        |> change(role: "blocked")
        |> Repo.update()

      conn =
        conn
        |> post(~p"/log_in", %{
          "user" => %{"email" => blocked_user.email, "password" => "hello world!"}
        })
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
    end
  end

  describe "DELETE /log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
