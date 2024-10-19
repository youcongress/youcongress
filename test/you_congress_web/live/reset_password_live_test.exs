defmodule YouCongressWeb.ResetPasswordLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  alias YouCongress.Repo

  alias YouCongress.Accounts

  describe "Reset password page" do
    test "renders reset password page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/reset_password")

      assert html =~ "Reset Password"
      assert html =~ "Enter your email to receive a password reset link"
    end

    test "sends a new reset password token", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "reset_password"
    end

    test "does not send reset password token if email is invalid", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/reset_password")

      {:ok, conn} =
        lv
        |> form("#reset_password_form", user: %{email: "unknown@example.com"})
        |> render_submit()
        |> follow_redirect(conn, "/")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"

      assert Repo.all(Accounts.UserToken) == []
    end
  end
end
