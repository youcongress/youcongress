defmodule YouCongressWeb.Plugs.AnalyticsConsentTest do
  use YouCongressWeb.ConnCase, async: true

  alias YouCongress.AnalyticsConsent
  alias YouCongressWeb.Plugs.AnalyticsConsent, as: AnalyticsConsentPlug

  @cookie_name "youcongress_cookie_consent"

  setup %{conn: conn} do
    conn = init_test_session(conn, %{})
    AnalyticsConsent.set_for_process(false)
    %{conn: conn}
  end

  test "grants consent only for an accepted cookie", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@cookie_name, "accepted")
      |> AnalyticsConsentPlug.call([])

    assert AnalyticsConsent.granted?()
    assert get_session(conn, :analytics_consent)
  end

  test "does not grant consent for another cookie value", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie(@cookie_name, "rejected")
      |> AnalyticsConsentPlug.call([])

    refute AnalyticsConsent.granted?()
    refute get_session(conn, :analytics_consent)
  end

  test "removes stale consent from the session", %{conn: conn} do
    conn =
      conn
      |> put_session(:analytics_consent, true)
      |> put_req_cookie(@cookie_name, "rejected")
      |> AnalyticsConsentPlug.call([])

    refute AnalyticsConsent.granted?()
    refute get_session(conn, :analytics_consent)
  end
end
