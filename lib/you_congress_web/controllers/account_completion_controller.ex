defmodule YouCongressWeb.AccountCompletionController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongressWeb.ReturnTo

  def dismiss_phone(conn, params) do
    {:ok, _user} = Accounts.dismiss_phone_verification_prompt(conn.assigns.current_user)
    redirect(conn, to: destination(conn, params))
  end

  def dismiss_newsletter(conn, params) do
    {:ok, _user} = Accounts.dismiss_newsletter_subscription_prompt(conn.assigns.current_user)
    redirect(conn, to: destination(conn, params))
  end

  def subscribe(conn, params) do
    {:ok, _user} = Accounts.welcome_update(conn.assigns.current_user, %{newsletter: true})

    conn
    |> put_flash(:info, "You are subscribed to YouCongress updates.")
    |> redirect(to: destination(conn, params))
  end

  def phone(conn, params) do
    redirect(conn,
      to: ~p"/sign_up?#{%{phone: "true", return_to: destination(conn, params)}}"
    )
  end

  defp destination(conn, params) do
    ReturnTo.sanitize(params["return_to"]) || referrer_path(conn) || ~p"/"
  end

  defp referrer_path(conn) do
    conn
    |> get_req_header("referer")
    |> List.first()
    |> ReturnTo.from_same_origin_url(conn.host)
  end
end
