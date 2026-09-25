defmodule YouCongressWeb.ContactLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  describe "contact page" do
    test "renders the form and prefills report details", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/contact?#{%{body: "http://example.com/c/42"}}")

      assert html =~ "Contact us"
      assert html =~ "Name"
      assert html =~ "Email"
      assert html =~ "Your website or social media link (optional)"
      assert html =~ "Message"
      assert html =~ "http://example.com/c/42"
    end

    test "prefills a subject and message from URL parameters", %{conn: conn} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/contact?#{%{subject: "Reconsider beta access", body: "I'd like to try it."}}"
        )

      assert has_element?(
               view,
               "#contact_subject[value='Reconsider beta access']"
             )

      assert has_element?(view, "#contact_body", "I'd like to try it.")
    end

    test "prefills the signed-in user's name and email", %{conn: conn} do
      user =
        YouCongress.AccountsFixtures.user_fixture()
        |> YouCongress.Repo.preload(:author)

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ user.author.name
      assert html =~ user.email
    end

    test "renders Turnstile when a site key is configured", %{conn: conn} do
      previous_site_key = Application.get_env(:you_congress, :turnstile_site_key)
      Application.put_env(:you_congress, :turnstile_site_key, "test-site-key")

      on_exit(fn ->
        if previous_site_key do
          Application.put_env(:you_congress, :turnstile_site_key, previous_site_key)
        else
          Application.delete_env(:you_congress, :turnstile_site_key)
        end
      end)

      {:ok, _view, html} = live(conn, ~p"/contact")

      assert html =~ ~s(id="turnstile-widget")
      assert html =~ ~s(data-sitekey="test-site-key")
      assert html =~ ~s(phx-hook="Turnstile")
    end

    test "validates required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      html =
        view
        |> form("#contact-form", contact: %{name: "", email: "", body: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
      refute_email_sent()
    end

    test "delivers a valid message", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/contact")

      html =
        view
        |> form("#contact-form",
          contact: %{
            name: "Ada Lovelace",
            email: "ada@example.com",
            website: "https://example.com/ada",
            subject: "Partnership question",
            body: "Can you help?"
          }
        )
        |> render_submit()

      assert html =~ "Your message has been sent."

      assert_email_sent(
        to: "hi@youcongress.org",
        reply_to: "ada@example.com",
        subject: "Partnership question",
        text_body: ~r/Name: Ada Lovelace.*https:\/\/example.com\/ada.*Can you help\?/s
      )
    end
  end
end
