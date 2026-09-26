defmodule YouCongressWeb.NewsletterLiveTest do
  use YouCongressWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Newsletters
  alias YouCongress.Newsletters.NewsletterConsent
  alias YouCongress.Repo

  describe "anonymous subscription" do
    test "requires an explicit email confirmation before subscribing an existing user", %{
      conn: conn
    } do
      user = user_fixture()
      refute user.newsletter

      {:ok, view, html} = live(conn, ~p"/subscribe")

      assert html =~ "Subscribe to YouCongress news"
      refute html =~ "Sign up with Google"

      html =
        view
        |> form("#newsletter-form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "Check your email"
      refute Accounts.get_user!(user.id).newsletter
      refute Newsletters.latest_consent(user.email)

      pending = Repo.get_by!(NewsletterConsent, email: user.email)
      refute pending.confirmed_at
      assert pending.source == "subscribe_page_anonymous"

      {:email, email} = assert_email_sent()
      assert email.subject == "Confirm your YouCongress newsletter subscription"
      [_, token] = Regex.run(~r{/newsletter/confirm/([A-Za-z0-9_-]+)}, email.text_body)

      {:ok, confirmation_view, confirmation_html} =
        live(conn, ~p"/newsletter/confirm/#{token}")

      assert confirmation_html =~ "Confirm subscription"
      refute Accounts.get_user!(user.id).newsletter

      assert render_click(confirmation_view, "confirm") =~
               "Your newsletter subscription is confirmed."

      assert Accounts.get_user!(user.id).newsletter
      consent = Newsletters.latest_consent(user.email)
      assert consent.id == pending.id
      assert consent.user_id == user.id
      assert consent.confirmed_at
      assert consent.token_hash == nil

      {:ok, replay_view, _html} = live(conn, ~p"/newsletter/confirm/#{token}")

      assert render_click(replay_view, "confirm") =~
               "This newsletter confirmation link is invalid or has expired."
    end

    test "confirms an address without creating an account", %{conn: conn} do
      email_address = unique_user_email()
      {:ok, view, _html} = live(conn, ~p"/subscribe")

      view
      |> form("#newsletter-form", user: %{email: email_address})
      |> render_submit()

      refute Accounts.get_user_by_email(email_address)
      {:email, email} = assert_email_sent()
      [_, token] = Regex.run(~r{/newsletter/confirm/([A-Za-z0-9_-]+)}, email.text_body)

      {:ok, confirmation_view, _html} = live(conn, ~p"/newsletter/confirm/#{token}")
      render_click(confirmation_view, "confirm")

      refute Accounts.get_user_by_email(email_address)
      assert Newsletters.latest_consent(email_address).action == :subscribe
    end
  end

  describe "authenticated subscription" do
    test "offers an Explore action when already subscribed", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.welcome_update(user, %{newsletter: true})
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/subscribe")

      assert html =~ "You are already subscribed."
      assert has_element?(view, ~s(a[href="/explore"]), "Explore")
      refute has_element?(view, "#newsletter-form")
    end

    test "prefills the form and subscribes the account email directly", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, html} = live(conn, ~p"/subscribe")

      assert html =~ ~s(id="newsletter-form")
      assert has_element?(view, ~s(input[name="user[email]"][value="#{user.email}"]))

      html =
        view
        |> form("#newsletter-form", user: %{email: user.email})
        |> render_submit()

      assert html =~ "Your newsletter subscription is confirmed."
      assert Accounts.get_user!(user.id).newsletter

      consent = Newsletters.latest_consent(user.email)
      assert consent.action == :subscribe
      assert consent.source == "subscribe_page_authenticated"
      assert consent.confirmed_at
      assert consent.user_id == user.id

      assert {:ok, _user} = Newsletters.subscribe_user(user, "duplicate_attempt")

      assert Repo.aggregate(
               from(consent in NewsletterConsent, where: consent.email == ^user.email),
               :count
             ) == 1
    end

    test "allows a different email and requires it to be confirmed", %{conn: conn} do
      user = user_fixture()
      alternate_email = unique_user_email()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/subscribe")

      html =
        view
        |> form("#newsletter-form", user: %{email: alternate_email})
        |> render_submit()

      assert html =~ "Check your email"
      refute Accounts.get_user!(user.id).newsletter

      pending = Repo.get_by!(NewsletterConsent, email: alternate_email)
      assert pending.user_id == user.id
      assert pending.source == "subscribe_page_authenticated"
      refute pending.confirmed_at

      {:email, email} = assert_email_sent()
      [_, token] = Regex.run(~r{/newsletter/confirm/([A-Za-z0-9_-]+)}, email.text_body)

      {:ok, confirmation_view, _html} = live(conn, ~p"/newsletter/confirm/#{token}")
      render_click(confirmation_view, "confirm")

      assert Accounts.get_user!(user.id).newsletter
      consent = Newsletters.latest_consent(alternate_email)
      assert consent.user_id == user.id
      assert consent.confirmed_at

      assert {:ok, _user} =
               user.id
               |> Accounts.get_user!()
               |> Newsletters.unsubscribe_user("alternate_email_test")

      refute Accounts.get_user!(user.id).newsletter
      assert Newsletters.latest_consent(alternate_email).action == :unsubscribe
    end
  end
end
