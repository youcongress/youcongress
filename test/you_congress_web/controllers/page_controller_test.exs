defmodule YouCongressWeb.PageControllerTest do
  use YouCongressWeb.ConnCase, async: true

  test "GET / loads successfully", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~
             "The biggest problem in the world is not climate change, war or poverty, but how we organise among ourselves to make good decisions and carry them out"
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
end
