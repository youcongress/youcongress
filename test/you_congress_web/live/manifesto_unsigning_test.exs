defmodule YouCongressWeb.ManifestoLive.UnsigningTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestosFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures
  alias YouCongress.Manifestos

  describe "Unsigning Manifestos" do
    test "user can unsign a manifesto", %{conn: conn} do
      user = user_fixture()
      manifesto = manifesto_fixture(user_id: user.id)
      voting = voting_fixture()
      Manifestos.create_section(%{manifesto_id: manifesto.id, voting_id: voting.id, body: "Paragraph 1"})

      # Sign first
      Manifestos.sign_manifesto(manifesto, user)
      assert Manifestos.signed?(manifesto, user)
      assert Manifestos.signatures_count(manifesto) == 1

      {:ok, show_live, _html} = live(conn, ~p"/manifestos/#{manifesto.slug}")

      # Log in via test helper if necessary, or assume live acting as user
      # Actually, better to log in first
      conn = log_in_user(conn, user)
      {:ok, show_live, _html} = live(conn, ~p"/manifestos/#{manifesto.slug}")

      assert show_live |> element("button", "Unsign") |> has_element?()

      # Click Unsign
      show_live |> element("button", "Unsign") |> render_click()

      refute Manifestos.signed?(manifesto, user)
      assert Manifestos.signatures_count(manifesto) == 0

      # Verify votes still exist
      assert YouCongress.Votes.get_by(voting_id: voting.id, author_id: user.author_id)

      # UI should update
      assert render(show_live) =~ "Sign Manifesto"
    end
  end
end
