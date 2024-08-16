defmodule YouCongressWeb.PageControllerTest do
  use YouCongressWeb.ConnCase, async: true

  test "GET / loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ "YouCongress"
  end

  test "GET /privacy loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    assert html_response(conn, 200) =~ "Privacy Policy"
  end

  test "GET /terms loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/terms")
    assert html_response(conn, 200) =~ "Terms and Conditions"
  end

  test "GET /about loads as a non-logged visitor", %{conn: conn} do
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About YouCongress"
  end

  test "GET /about loads as a user", %{conn: conn} do
    conn = log_in_as_user(conn)
    conn = get(conn, ~p"/about")
    assert html_response(conn, 200) =~ "About YouCongress"
  end

  test "GET /faq loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/faq")
    assert html_response(conn, 200) =~ "Frequently asked questions"
  end

  test "GET /email-login-waiting-list", %{conn: conn} do
    conn = get(conn, ~p"/email-login-waiting-list")
    assert html_response(conn, 200) =~ "Waiting list for email/password login – YouCongress"
  end

  test "POST /email-login-waiting-list/thanks", %{conn: conn} do
    conn = get(conn, ~p"/email-login-waiting-list/thanks")
    assert html_response(conn, 302) =~ "redirected"
  end
end
