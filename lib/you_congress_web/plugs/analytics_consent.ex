defmodule YouCongressWeb.Plugs.AnalyticsConsent do
  @moduledoc """
  Makes the browser's analytics preference available to controllers and LiveViews.
  """

  import Plug.Conn

  alias YouCongress.AnalyticsConsent

  @cookie_name "youcongress_cookie_consent"
  @session_key :analytics_consent

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)
    granted? = conn.cookies[@cookie_name] == "accepted"

    AnalyticsConsent.set_for_process(granted?)
    sync_session_consent(conn, granted?)
  end

  defp sync_session_consent(conn, true) do
    if get_session(conn, @session_key) == true do
      conn
    else
      put_session(conn, @session_key, true)
    end
  end

  defp sync_session_consent(conn, false) do
    if get_session(conn, @session_key) == true do
      delete_session(conn, @session_key)
    else
      conn
    end
  end
end
