defmodule YouCongressWeb.UserConfirmationController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongressWeb.UserAuth

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        if Accounts.blocked_role?(user) do
          conn
          |> put_flash(
            :error,
            "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
          )
          |> redirect(to: ~p"/log_in")
        else
          conn
          |> UserAuth.log_in_user_without_redirect(user)
          |> redirect(to: ~p"/sign_up")
        end

      :error ->
        conn
        |> put_flash(:error, "User confirmation link is invalid or it has expired.")
        |> redirect(to: ~p"/log_in")
    end
  end
end
