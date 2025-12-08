defmodule YouCongressWeb.ManifestLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestsFixtures

  describe "Index" do
    test "lists all active manifests", %{conn: conn} do
      manifest = manifest_fixture(active: true)
      {:ok, _index_live, html} = live(conn, ~p"/manifests")

      assert html =~ "Manifests"
      assert html =~ manifest.title
    end

    test "saves new manifest", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/manifests")

      assert index_live |> element("a", "New Manifest") |> render_click() =~
               "New Manifest"

      assert_patch(index_live, ~p"/manifests/new")

      assert index_live
             |> form("#manifest-form", manifest: %{title: "New Manifest Title", slug: "new-manifest-slug", active: "true"})
             |> render_submit()

      assert_patch(index_live, ~p"/manifests")

      html = render(index_live)
      assert html =~ "Manifest created successfully"
      assert html =~ "New Manifest Title"
    end
  end
end
