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
  end
end
