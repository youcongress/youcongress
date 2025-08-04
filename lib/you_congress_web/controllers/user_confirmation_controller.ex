defmodule YouCongressWeb.UserConfirmationController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongressWeb.UserAuth

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user_without_redirect(user)
        |> redirect(to: ~p"/sign_up")

      :error ->
        conn
        |> put_flash(:error, "User confirmation link is invalid or it has expired.")
        |> redirect(to: ~p"/log_in")
    end
  end
end
