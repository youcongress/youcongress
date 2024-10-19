defmodule YouCongressWeb.ResetPasswordTokenLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  setup do
    user = user_fixture()

    token =
      extract_user_token(fn url ->
        Accounts.deliver_user_reset_password_instructions(user, url)
      end)

    %{user: user, token: token}
  end

  describe "Reset password page" do
    test "renders reset password with valid token", %{conn: conn, token: token} do
      {:ok, _lv, html} = live(conn, ~p"/reset_password/#{token}")

      assert html =~ "Reset Password"
    end

    test "redirects if reset password token is invalid", %{conn: conn} do
      {:error, {:redirect, %{to: path, flash: flash}}} = live(conn, ~p"/reset_password/invalid")

      assert path == "/"
      assert flash["error"] == "Reset password link is invalid or it has expired."
    end

    test "renders errors for invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/reset_password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{
            password: "short",
            password_confirmation: "does not match"
          }
        )
        |> render_submit()

      assert result =~ "Reset Password"
      assert result =~ "should be at least 8 character(s)"
      assert result =~ "does not match password"
    end

    test "resets password once", %{conn: conn, token: token, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/reset_password/#{token}")

      {:ok, conn} =
        lv
        |> form("#reset_password_form",
          user: %{
            password: "new valid password",
            password_confirmation: "new valid password"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/log_in")

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password reset successfully"
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "does not reset password on invalid data", %{conn: conn, token: token} do
      {:ok, lv, _html} = live(conn, ~p"/reset_password/#{token}")

      result =
        lv
        |> form("#reset_password_form",
          user: %{
            password: "short",
            password_confirmation: "does not match"
          }
        )
        |> render_submit()

      assert result =~ "Reset Password"
      assert result =~ "should be at least 8 character(s)"
      assert result =~ "does not match password"
    end
  end
end
