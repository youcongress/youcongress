defmodule YouCongressWeb.CouncilNavigationTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  test "the main navigation shows Sign up for guests and Profile for signed-in users", %{
    conn: conn
  } do
    for user <- [nil, user_fixture(), admin_fixture()] do
      conn = if user, do: log_in_user(conn, user), else: conn
      html = conn |> get("/about") |> html_response(200) |> Floki.parse_document!()
      links = Floki.find(html, "nav[aria-label='Main navigation'] a")
      assert length(links) == 5

      assert links |> Enum.drop(1) |> Enum.map(&(Floki.text(&1) |> String.trim())) ==
               ["My Council", "Explore", "About", if(user, do: "Profile", else: "Sign up")]

      if is_nil(user) do
        assert Floki.attribute(List.last(links), "href") == ["/sign_up"]
      end

      assert Floki.attribute(hd(links), "href") == ["https://github.com/youcongress/youcongress"]
    end
  end

  test "Council tabs keep My lists accessible and Trust 30 admin-only", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, council, _} = live(conn, "/council?step=mine")
    assert has_element?(council, "nav[aria-label='My Council'] a[href='/lists']", "My lists")
    refute has_element?(council, "nav[aria-label='My Council'] a[href='/trust']")

    {:ok, lists, _} =
      council
      |> element("nav[aria-label='My Council'] a", "My lists")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(lists, "nav[aria-label='My Council'] a[aria-current=page]", "My lists")
    assert has_element?(lists, "nav[aria-label='My Council'] a[href='/council']")
    {:ok, admin, _} = live(log_in_user(build_conn(), admin_fixture()), "/council?step=mine")
    assert has_element?(admin, "nav[aria-label='My Council'] a[href='/trust']", "Trust 30")
  end

  test "Trust 30 shows the same tabs with its active state", %{conn: conn} do
    {:ok, view, _} = live(log_in_user(conn, admin_fixture()), "/trust")
    assert has_element?(view, "nav[aria-label='My Council'] a[aria-current=page]", "Trust 30")
    assert has_element?(view, "nav[aria-label='My Council'] a[href='/lists']", "My lists")
  end

  test "the removed Updates URL returns 404, including for admins", %{conn: conn} do
    for user <- [nil, user_fixture(), admin_fixture()] do
      conn = if user, do: log_in_user(conn, user), else: conn
      assert conn |> get("/trust/updates") |> response(404) == "Not found"
    end
  end
end
