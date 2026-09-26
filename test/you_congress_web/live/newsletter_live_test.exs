defmodule YouCongressWeb.NewsletterLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  test "embeds the official Substack signup form", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/subscribe")

    assert html =~ "Subscribe to YouCongress news"

    assert has_element?(
             view,
             ~s(iframe#substack-signup[src="https://youcongress.substack.com/embed"])
           )

    refute has_element?(view, "#newsletter-form")
  end

  test "uses Substack for signed-in users too", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/subscribe")

    assert has_element?(
             view,
             ~s(iframe#substack-signup[src="https://youcongress.substack.com/embed"])
           )
  end
end
