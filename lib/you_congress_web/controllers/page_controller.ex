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
end
