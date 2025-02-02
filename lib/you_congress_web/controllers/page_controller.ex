defmodule YouCongressWeb.PageController do
  use YouCongressWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def terms(conn, _params) do
    render(conn, :terms)
  end

  def privacy_policy(conn, _params) do
    render(conn, :privacy_policy)
  end

  def waiting_list(conn, _params) do
    render(conn, :waiting_list, layout: false)
  end

  def about(conn, _params) do
    render(conn, :about)
  end

  def faq(conn, _params) do
    render(conn, :faq)
  end

  def redirect_to_questions(conn, _params) do
    conn
    |> redirect(to: ~p"/")
    |> halt()
  end

  def email_login_waiting_list(conn, _params) do
    render(conn, :email_login_waiting_list, layout: false)
  end

  def email_login_waiting_list_thanks(conn, _params) do
    conn
    |> put_flash(:info, "Thanks for joining the waiting list! We'll be in touch.")
    |> redirect(to: ~p"/")
  end
end
