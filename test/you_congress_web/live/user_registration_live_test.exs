defmodule YouCongressWeb.UserRegistrationLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sign_up")

      assert html =~ "Register for an account"
      assert html =~ "Log in"
      assert html =~ "Create Account"
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
