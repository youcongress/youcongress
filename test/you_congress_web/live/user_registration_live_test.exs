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
end
