defmodule YouCongressWeb.UserRegistrationLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Accounts.UserToken
  alias YouCongress.Repo

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sign_up")

      assert html =~ "Register for an account"
      assert html =~ "Log in"
      assert html =~ "Continue with email"
      refute html =~ ~s(type="password")
    end

    test "creates a passwordless account and emails a magic link", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/sign_up?return_to=/settings")

      html =
        lv
        |> form("#registration_form", user: %{name: "New User", email: email})
        |> render_submit()

      assert html =~ "Check your email"
      assert html =~ "expires in 15 minutes"

      user = Accounts.get_user_by_email(email)
      assert user
      assert user.hashed_password == nil
      assert user.email_confirmed_at == nil
      assert Repo.get_by(UserToken, user_id: user.id, context: "magic_login")

      assert_email_sent(fn email_message ->
        assert email_message.subject == "Confirm your YouCongress email"
        assert email_message.text_body =~ "Confirm your email"
        assert email_message.html_body =~ ">Confirm your email</a>"
      end)
    end

    test "subscription page creates a newsletter subscriber", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, html} = live(conn, ~p"/subscribe")

      assert html =~
               "Subscribe to YouCongress news on AI governance, safety, and its impact on jobs"

      assert html =~ "Subscribe"
      refute html =~ "Sign up with Google"

      html =
        lv
        |> form("#registration_form", user: %{name: "News Reader", email: email})
        |> render_submit()

      assert html =~ "Check your email"

      user = Accounts.get_user_by_email(email)
      assert user.newsletter
      assert Repo.get_by(UserToken, user_id: user.id, context: "magic_login")
    end

    test "preserves return_to in OAuth links", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sign_up?return_to=/p/test-statement")

      assert html =~ ~s(href="/auth/google?return_to=%2Fp%2Ftest-statement")
    end

    test "a user with a confirmed email returns directly to what they were doing", %{conn: conn} do
      user = user_fixture(%{}, %{name: "New user", twin_origin: false}, false)
      {:ok, user} = Accounts.confirm_user_email(user)
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/p/test-statement"}}} =
               live(conn, ~p"/sign_up?return_to=/p/test-statement")
    end

    test "phone verification remains available when explicitly requested", %{conn: conn} do
      user = user_fixture(%{}, %{name: "New user", twin_origin: false}, false)
      {:ok, user} = Accounts.confirm_user_email(user)
      conn = log_in_user(conn, user)

      {:ok, lv, html} = live(conn, ~p"/sign_up?phone=true&return_to=/settings")

      assert html =~ "Enter your mobile phone number"
      assert html =~ "Maybe later"

      render_click(lv, "skip_phone")
      assert Accounts.get_user!(user.id).phone_verification_prompt_dismissed_at
    end
  end
end
