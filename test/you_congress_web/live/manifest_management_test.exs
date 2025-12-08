defmodule YouCongressWeb.ManifestManagementTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures

  describe "Edit Manifest" do
    test "saves new section", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      manifest = manifest_fixture(user_id: user.id)

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}/edit")

      assert view
             |> form("form", manifest_section: %{body: "New Paragraph", voting_id: ""})
             |> render_submit()

      assert render(view) =~ "New Paragraph"
    end

    test "deletes section", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      manifest = manifest_fixture(user_id: user.id)
      YouCongress.Manifests.create_section(%{manifest_id: manifest.id, body: "To be deleted"})

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}/edit")

      assert has_element?(view, "#sections", "To be deleted")

      view
      |> element("button[phx-click=\"delete_section\"]")
      |> render_click()

      refute has_element?(view, "#sections", "To be deleted")
    end

    test "links motion", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      manifest = manifest_fixture(user_id: user.id)
      voting = voting_fixture(title: "AI Safety")

      {:ok, view, _html} = live(conn, ~p"/manifests/#{manifest.slug}/edit")

      assert view
             |> form("form", manifest_section: %{body: "With Motion", voting_id: voting.id})
             |> render_submit()

      assert render(view) =~ "Linked Motion: AI Safety"
    end
  end
end
