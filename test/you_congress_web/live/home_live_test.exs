defmodule YouCongressWeb.HomeLiveTest do
  use YouCongressWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures

  describe "Home page" do
    test "renders the two-layer messaging", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Two layers of YouCongress"
      assert html =~ "Data layer"
      assert html =~ "Participation layer"
      assert html =~ "Search AI quotes, people, policies..."
    end

    test "search surfaces matching statements", %{conn: conn} do
      statement_fixture(title: "AI Safety Bill")
      statement_fixture(title: "Tax Reform")

      {:ok, view, _html} = live(conn, ~p"/")

      view
      |> form("form[phx-change=search]", %{"search" => "AI"})
      |> render_change()

      rendered = render(view)
      assert rendered =~ "<b>AI</b> Safety Bill"
      refute rendered =~ "Tax Reform"
    end
  end
end
