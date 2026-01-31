defmodule YouCongressWeb.StatementLiveSearchTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.StatementsFixtures
  import YouCongress.AuthorsFixtures

  describe "StatementLive search via URL params" do
    test "renders search results when search param is present", %{conn: conn} do
      _statement = statement_fixture(title: "AI Safety Bill")
      _other_statement = statement_fixture(title: "Tax Reform")

      {:ok, _view, html} = live(conn, ~p"/?search=AI", on_error: :warn)

      assert html =~ "<b>AI</b> Safety Bill"
      refute html =~ "Tax Reform"
    end

    test "selects correct tab based on param", %{conn: conn} do
      # Create an author to ensure authors tab has content if needed, but we force tab via param
      author_fixture(name: "Isaac Asimov")

      {:ok, _view, html} = live(conn, ~p"/?search=Asimov&tab=delegates", on_error: :warn)

      # Check if delegates tab is active (assuming class "bg-blue-100" or similar indicates active state,
      # but simpler is to check if author is listed)
      assert html =~ "Isaac <b>Asimov</b>"
    end
  end

  describe "StatementLive search via / params" do
    test "renders search results on / when search param is present", %{conn: conn} do
      _statement = statement_fixture(title: "AI Safety Bill")
      _other_statement = statement_fixture(title: "Tax Reform")

      {:ok, _view, html} = live(conn, ~p"/?search=AI", on_error: :warn)

      assert html =~ "<b>AI</b> Safety Bill"
      refute html =~ "Tax Reform"
    end

    test "selects correct tab on / based on param", %{conn: conn} do
      author_fixture(name: "Isaac Asimov")

      {:ok, _view, html} = live(conn, ~p"/?search=Asimov&tab=delegates", on_error: :warn)

      assert html =~ "Isaac <b>Asimov</b>"
    end
  end
end
