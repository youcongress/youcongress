defmodule YouCongressWeb.UserConfirmationController do
  use YouCongressWeb, :controller

  def confirm(conn, _params) do
    conn
    |> put_flash(
      :info,
      "We now confirm accounts with six-digit codes. Please enter the code from your email on the sign up screen."
    )
    |> redirect(to: ~p"/sign_up")
  end
end
