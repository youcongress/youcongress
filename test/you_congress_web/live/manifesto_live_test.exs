defmodule YouCongressWeb.ManifestoLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.ManifestosFixtures
  import Swoosh.TestAssertions

  describe "Index" do
    test "lists all active manifestos", %{conn: conn} do
      manifesto = manifesto_fixture(active: true)
      {:ok, _index_live, html} = live(conn, ~p"/manifestos")

      assert html =~ "Manifestos"
      assert html =~ manifesto.title
    end
  end

  describe "Manifesto creation" do
    setup [:register_and_log_in_user]

    test "saves new manifesto", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/manifestos")

      assert index_live |> element("a", "New Manifesto") |> render_click() =~ "New Manifesto"

      assert_patch(index_live, ~p"/m/new")

      assert index_live
             |> form("#manifesto-form",
               manifesto: %{title: "New Manifesto Title", slug: "new-manifesto-slug", active: "true"}
             )
             |> render_submit()

      assert_patch(index_live, ~p"/manifestos")

      html = render(index_live)
      assert html =~ "Manifesto created successfully"
      assert html =~ "New Manifesto Title"
    end
  end

  describe "Show" do
    test "displays sign up form for unauthenticated users", %{conn: conn} do
      manifesto = manifesto_fixture()
      {:ok, show_live, html} = live(conn, ~p"/m/#{manifesto.slug}")

      assert html =~ "Sign this Manifesto"
      assert has_element?(show_live, "form[phx-submit=sign_up_and_sign]")
    end

    test "registers user and sends validation email", %{conn: conn} do
      manifesto = manifesto_fixture()
      {:ok, show_live, _html} = live(conn, ~p"/m/#{manifesto.slug}")

      email = "newuser@example.com"
      name = "New User"

      show_live
      |> form("form[phx-submit=sign_up_and_sign]", name: name, email: email, newsletter: "on")
      |> render_submit()

      assert render(show_live) =~ "Account created. Please check your email"
      assert_email_sent(to: email)

      user = YouCongress.Accounts.get_user_by_email(email)
      assert user.newsletter == true
    end

    test "shows creator name and link", %{conn: conn} do
      user = YouCongress.AccountsFixtures.user_fixture()
      manifesto = manifesto_fixture(user_id: user.id)
      # Ensure author is loaded for the fixture or fetch it
      manifesto = YouCongress.Manifestos.get_manifesto!(manifesto.id) |> YouCongress.Repo.preload(user: :author)

      {:ok, _show_live, html} = live(conn, ~p"/m/#{manifesto.slug}")

      assert html =~ "Created by"
      assert html =~ manifesto.user.author.name
      assert html =~ ~p"/x/#{manifesto.user.author.twitter_username}"
    end

    test "toggles creator name visibility", %{conn: conn} do
      user = YouCongress.AccountsFixtures.user_fixture()
      manifesto = manifesto_fixture(user_id: user.id, show_author: false)

      {:ok, _show_live, html} = live(conn, ~p"/m/#{manifesto.slug}")
      refute html =~ "Created by"

      {:ok, manifesto} = YouCongress.Manifestos.update_manifesto(manifesto, %{show_author: true})
      {:ok, _show_live, html} = live(conn, ~p"/m/#{manifesto.slug}")
      assert html =~ "Created by"
    end
  end

  describe "manifesto creation requires authentication" do
    test "redirects anonymous visitors", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/log_in"}}} = live(conn, ~p"/m/new")
    end
  end
end
