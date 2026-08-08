defmodule YouCongressWeb.UserRegistrationLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

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
  end

  describe "finishing the sign-up" do
    test "skipping the phone step sends AI Policy sign-ups straight to /ai-welcome", %{conn: conn} do
      user = user_with_confirmed_email_only()

      {:ok, lv, html} = conn |> log_in_user(user) |> live(~p"/sign_up?return_to=%2Fai-welcome")

      assert html =~ "Enter your mobile phone number"

      lv |> element("a", "Maybe later") |> render_click()

      assert_push_event(lv, "session-login", %{
        redirect_to: "/ai-welcome",
        return_to: "/ai-welcome"
      })
    end

    test "skipping the phone step sends other sign-ups to /welcome", %{conn: conn} do
      user = user_with_confirmed_email_only()

      {:ok, lv, _html} =
        conn |> log_in_user(user) |> live(~p"/sign_up?return_to=%2Fp%2Ftest-statement")

      lv |> element("a", "Maybe later") |> render_click()

      assert_push_event(lv, "session-login", %{
        redirect_to: "/welcome?return_to=%2Fp%2Ftest-statement"
      })
    end

    test "a fully registered user is sent straight to /ai-welcome", %{conn: conn} do
      user = YouCongress.AccountsFixtures.user_fixture()

      assert {:error, {:redirect, %{to: "/ai-welcome"}}} =
               conn |> log_in_user(user) |> live(~p"/sign_up?return_to=%2Fai-welcome")
    end
  end

  defp user_with_confirmed_email_only do
    user = YouCongress.AccountsFixtures.user_fixture(%{}, nil, false)
    {:ok, user} = YouCongress.Accounts.confirm_user_email(user)
    user
  end
end
