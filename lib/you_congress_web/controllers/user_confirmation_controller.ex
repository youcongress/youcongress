defmodule YouCongressWeb.UserConfirmationController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.UserAuth

  def confirm(conn, %{"token" => token} = params) do
    case Accounts.confirm_user(token) do
      {:ok, user} ->
        if Permissions.blocked?(user) do
          conn
          |> put_flash(
            :error,
            "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
          )
          |> redirect(to: ~p"/log_in")
        else
          conn = UserAuth.log_in_user_without_redirect(conn, user)

          if manifesto_slug = params["manifesto_slug"] do
            manifesto = YouCongress.Manifestos.get_manifesto_by_slug!(manifesto_slug)
            YouCongress.Manifestos.sign_manifesto(manifesto, user)

            conn
            |> put_flash(:info, "You have successfully signed the manifesto.")
            |> redirect(to: ~p"/m/#{manifesto_slug}")
          else
            conn
            |> redirect(to: ~p"/sign_up")
          end
        end

      :error ->
        conn
        |> put_flash(:error, "User confirmation link is invalid or it has expired.")
        |> redirect(to: ~p"/log_in")
    end
  end
end
