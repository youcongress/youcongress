defmodule YouCongressWeb.UserSessionControllerTest do
  use YouCongressWeb.ConnCase, async: true

  alias YouCongress.Repo
  alias YouCongress.Accounts
  alias YouCongress.Accounts.UserToken
  import YouCongress.AccountsFixtures
  import Phoenix.LiveViewTest
  import Ecto.Changeset

  setup do
    %{user: user_fixture()}
  end

  describe "GET /log_in" do
    test "uses the same-origin referrer as return_to for OAuth links", %{conn: conn} do
      conn = put_req_header(conn, "referer", "http://www.example.com/p/test-statement")

      {:ok, _view, html} = live(conn, ~p"/log_in")

      assert html =~ ~s(href="/auth/google?return_to=%2Fp%2Ftest-statement")
    end

    test "offers magic-link login", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/log_in")

      assert html =~ ~s(id="magic_link_form")
      assert html =~ "Email me a sign-in link"
    end
  end

  describe "POST /log_in/magic-link" do
    test "creates a magic login token without disclosing account existence", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> post(~p"/log_in/magic-link", %{
          "user" => %{
            "email" => user.email,
            "return_to" => "/p/ai-alignment-public-deliberation"
          }
        })
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"
      assert Repo.get_by(UserToken, user_id: user.id, context: "magic_login")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
               "If an account exists for that email, we'll send a sign-in link shortly."

      missing_conn =
        conn
        |> recycle()
        |> post(~p"/log_in/magic-link", %{
          "user" => %{"email" => "missing@example.com"}
        })
        |> fetch_flash()

      assert redirected_to(missing_conn) == ~p"/log_in"

      assert Phoenix.Flash.get(missing_conn.assigns.flash, :info) ==
               Phoenix.Flash.get(conn.assigns.flash, :info)
    end

    test "does not issue a link for a blocked account", %{conn: conn, user: user} do
      {:ok, blocked_user} = Accounts.update_role(user, "blocked")

      conn =
        post(conn, ~p"/log_in/magic-link", %{
          "user" => %{"email" => blocked_user.email}
        })

      assert redirected_to(conn) == ~p"/log_in"
      refute Repo.get_by(UserToken, user_id: user.id, context: "magic_login")
    end
  end

  describe "magic-link confirmation" do
    test "a click logs in, consumes the token, and honors a safe return path", %{
      conn: conn,
      user: user
    } do
      token = magic_login_token(user)

      conn =
        get(conn, ~p"/log_in/magic-link/#{token}?return_to=/settings")

      assert redirected_to(conn) == ~p"/settings"
      assert get_session(conn, :user_token)
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
      refute Repo.get_by(UserToken, user_id: user.id, context: "magic_login")
    end

    test "a registration link confirms the email and logs in", %{conn: conn} do
      user = user_fixture(%{}, %{}, false)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_registration_magic_link_instructions(user, url)
        end)

      conn = get(conn, ~p"/log_in/magic-link/#{token}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
      refute Phoenix.Flash.get(conn.assigns.flash, :info)
      assert Accounts.get_user!(user.id).email_confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id, context: "magic_login")
    end

    test "rejects an invalid token", %{conn: conn} do
      conn =
        conn
        |> get(~p"/log_in/magic-link/invalid")
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "This sign-in link is invalid or has expired."
    end

    test "rejects an unsafe return path", %{conn: conn, user: user} do
      token = magic_login_token(user)

      conn =
        get(
          conn,
          ~p"/log_in/magic-link/#{token}?return_to=https%3A%2F%2Fevil.example%2Fphishing"
        )

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end
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

  defp magic_login_token(user) do
    extract_user_token(fn url ->
      Accounts.deliver_user_magic_login_instructions(user, url)
    end)
  end
end
