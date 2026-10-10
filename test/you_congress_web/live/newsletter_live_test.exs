defmodule YouCongressWeb.NewsletterLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  test "links to the official Substack signup page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/subscribe")

    assert html =~ "Subscribe to YouCongress news"

    assert has_element?(
             view,
             ~s(a#substack-signup[href="https://youcongress.substack.com/subscribe"][target="_blank"])
           )

    refute has_element?(view, "#newsletter-form")
  end

  test "uses Substack for signed-in users too", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/subscribe")

    assert has_element?(
             view,
             ~s(a#substack-signup[href="https://youcongress.substack.com/subscribe"][target="_blank"])
           )
  end
end
