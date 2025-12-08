defmodule YouCongressWeb.ManifestLive.UnsigningTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures
  alias YouCongress.Manifests

  describe "Unsigning Manifests" do
    test "user can unsign a manifest", %{conn: conn} do
      user = user_fixture()
      manifest = manifest_fixture(user_id: user.id)
      voting = voting_fixture()
      Manifests.create_section(%{manifest_id: manifest.id, voting_id: voting.id, body: "Paragraph 1"})

      # Sign first
      Manifests.sign_manifest(manifest, user)
      assert Manifests.signed?(manifest, user)
      assert Manifests.signatures_count(manifest) == 1

      {:ok, show_live, _html} = live(conn, ~p"/manifests/#{manifest.slug}")

      # Log in via test helper if necessary, or assume live acting as user
      # Actually, better to log in first
      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, ~p"/manifests/#{manifest.slug}")

      assert show_live |> element("button", "Unsign") |> has_element?()

      # Click Unsign
      show_live |> element("button", "Unsign") |> render_click()

      refute Manifests.signed?(manifest, user)
      assert Manifests.signatures_count(manifest) == 0

      # Verify votes still exist
      assert YouCongress.Votes.get_by(voting_id: voting.id, author_id: user.author_id)

      # UI should update
      assert render(show_live) =~ "Sign Manifest"
    end
  end
end
