defmodule YouCongressWeb.ManifestoLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestosFixtures

  describe "Index" do
    test "lists all active manifestos", %{conn: conn} do
      manifesto = manifesto_fixture(active: true)
      {:ok, _index_live, html} = live(conn, ~p"/manifestos")

      assert html =~ "Manifestos"
      assert html =~ manifesto.title
    end

    test "saves new manifesto", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/manifestos")

      assert index_live |> element("a", "New Manifesto") |> render_click() =~
               "New Manifesto"

      assert_patch(index_live, ~p"/manifestos/new")

      assert index_live
             |> form("#manifesto-form", manifesto: %{title: "New Manifesto Title", slug: "new-manifesto-slug", active: "true"})
             |> render_submit()

      assert_patch(index_live, ~p"/manifestos")

      html = render(index_live)
      assert html =~ "Manifesto created successfully"
      assert html =~ "New Manifesto Title"
    end
  end
end
