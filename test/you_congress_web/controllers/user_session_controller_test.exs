defmodule YouCongressWeb.UserSessionControllerTest do
  use YouCongressWeb.ConnCase, async: true

  alias YouCongress.Repo
  alias YouCongress.Accounts
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

    test "redirects to form return_to after successful login", %{conn: conn} do
      password = valid_user_password()
      email = unique_user_email()
      {:ok, %{user: user}} = Accounts.register_user(%{"email" => email, "password" => password})

      conn =
        post(conn, ~p"/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => password,
            "return_to" => "/p/ai-alignment-public-deliberation"
          }
        })

      assert redirected_to(conn) == "/p/ai-alignment-public-deliberation"
      assert get_session(conn, :user_token)
    end
  end

  describe "POST /users/live_login" do
    test "stores registration_return_to for live registration login", %{conn: conn, user: user} do
      token = Accounts.generate_live_login_token(user)

      conn =
        post(conn, ~p"/users/live_login", %{
          "token" => token,
          "return_to" => "/p/ai-alignment-public-deliberation"
        })

      assert json_response(conn, 200) == %{"success" => true}
      assert get_session(conn, :registration_return_to) == "/p/ai-alignment-public-deliberation"
      assert get_session(conn, :user_token)
    end
  end

  describe "DELETE /log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
