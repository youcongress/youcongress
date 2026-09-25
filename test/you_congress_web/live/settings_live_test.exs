defmodule YouCongressWeb.SettingsLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.CountriesFixtures

  alias YouCongress.{Accounts, Authors, Newsletters}
  alias YouCongress.Accounts.UserToken
  alias YouCongress.Repo

  defp create_user(_) do
    current_user = user_fixture(%{}, %{name: "Someone"})
    %{current_user: current_user}
  end

  describe "Settings" do
    setup [:create_user]

    test "Non-logged visitors can't load the page", %{conn: conn} do
      {:error,
       {:redirect, %{flash: %{"error" => "You must log in to access this page."}, to: "/log_in"}}} =
        live(conn, ~p"/settings")
    end

    test "Logged users can load the page", %{conn: conn, current_user: current_user} do
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
      assert html =~ "Name: Someone"
      assert html =~ "YouCongress username"
      assert html =~ "author[username]"
      assert html =~ "reserved as a special perk"

      assert has_element?(
               settings_live,
               "a[href='mailto:hector@youcongress.org']",
               "hector@youcongress.org"
             )
    end

    test "users can set a normalized YouCongress username", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      html =
        render_submit(settings_live, "save", %{
          "author" => %{"username" => "  My_Profile  "}
        })

      assert html =~ "Settings updated successfully"
      assert Authors.get_author!(current_user.author_id).username == "my_profile"
      assert has_element?(settings_live, "input[name='author[username]'][value='my_profile']")
    end

    test "YouCongress usernames must be unique", %{
      conn: conn,
      current_user: current_user
    } do
      _other_user = user_fixture(%{}, %{name: "Other", username: "already_taken"})

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      assert render_submit(settings_live, "save", %{
               "author" => %{"username" => "ALREADY_TAKEN"}
             }) =~ "has already been taken"

      assert Authors.get_author!(current_user.author_id).username == nil
    end

    test "YouCongress usernames must contain between five and fifteen characters", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      assert render_submit(settings_live, "save", %{
               "author" => %{"username" => "four"}
             }) =~ "should be at least 5 character(s)"

      assert render_submit(settings_live, "save", %{
               "author" => %{"username" => "abcdefghijklmnop"}
             }) =~ "should be at most 15 character(s)"

      assert Authors.get_author!(current_user.author_id).username == nil
    end

    test "users without a verified phone see a link to verify it", %{conn: conn} do
      current_user = user_fixture(%{}, %{name: "Someone", twin_origin: false}, false)
      {:ok, current_user} = Accounts.confirm_user_email(current_user)

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "Verify with phone"

      assert settings_live
             |> element("a", "Verify with phone")
             |> render() =~ "phone=true"
    end

    test "users without a verified phone can select their country from a dropdown", %{
      conn: conn
    } do
      country = country_fixture(name: "Settings Dropdown Spain", phone_prefix: "+34")

      current_user = user_fixture(%{}, %{name: "Someone", twin_origin: false}, false)
      {:ok, current_user} = Accounts.confirm_user_email(current_user)

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "author[country_id]"
      assert html =~ "Settings Dropdown Spain"

      render_submit(settings_live, "save", %{
        "author" => %{
          "name" => "Spoofed Name",
          "bio" => "Spoofed bio",
          "country_id" => country.id,
          "twitter_username" => "spoofed_x",
          "google_id" => "spoofed_google",
          "public_figure" => "true",
          "twin_enabled" => "false",
          "verified" => "true"
        }
      })

      author = Authors.get_author!(current_user.author_id)
      assert author.name == "Someone"
      assert author.bio != "Spoofed bio"
      assert author.country_id == country.id
      refute author.twitter_username == "spoofed_x"
      refute author.google_id == "spoofed_google"
      refute author.public_figure
      assert author.twin_enabled
      refute author.verified
    end

    test "password users can update safe profile fields only", %{conn: conn} do
      country = country_fixture(name: "Settings Password User Spain", phone_prefix: "+34")

      {:ok, %{user: current_user}} =
        Accounts.register_user(
          %{
            "email" => "settings-password@example.com",
            "password" => "validpassword123"
          },
          %{
            "name" => "Password User",
            "bio" => "Old bio"
          }
        )

      {:ok, current_user} = Accounts.confirm_user_email(current_user)

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      render_submit(settings_live, "save", %{
        "author" => %{
          "name" => "Updated Password User",
          "bio" => "Updated bio",
          "country_id" => country.id,
          "twitter_id_str" => "12345",
          "twitter_username" => "spoofed_x",
          "google_id" => "spoofed_google",
          "profile_image_url" => "https://example.com/pic.jpg",
          "public_figure" => "true",
          "twin_enabled" => "false",
          "verified" => "true"
        }
      })

      author = Authors.get_author!(current_user.author_id)
      assert author.name == "Updated Password User"
      assert author.bio == "Updated bio"
      assert author.country_id == country.id
      assert author.twitter_id_str == nil
      assert author.twitter_username == nil
      assert author.google_id == nil
      assert author.profile_image_url == nil
      refute author.public_figure
      assert author.twin_enabled
      assert author.verified == nil
    end

    test "phone verified users don't see the verify with phone link", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, _settings_live, html} = live(conn, ~p"/settings")

      refute html =~ "Verify with phone"
    end

    test "users can manage the newsletter subscription", %{
      conn: conn,
      current_user: current_user
    } do
      {:ok, current_user} = Accounts.welcome_update(current_user, %{newsletter: false})
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "Email updates"
      assert has_element?(settings_live, "button[phx-click='subscribe_newsletter']", "Subscribe")

      render_click(settings_live, "subscribe_newsletter")
      assert Accounts.get_user!(current_user.id).newsletter
      assert Newsletters.latest_consent(current_user.email).action == :subscribe

      assert has_element?(
               settings_live,
               "button[phx-click='unsubscribe_newsletter']",
               "Unsubscribe"
             )

      render_click(settings_live, "unsubscribe_newsletter")
      user = Accounts.get_user!(current_user.id)
      refute user.newsletter
      assert user.newsletter_subscription_prompt_dismissed_at
      consent = Newsletters.latest_consent(current_user.email)
      assert consent.action == :unsubscribe
      assert consent.source == "settings"
    end

    test "users can create and revoke their own API keys", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      html =
        settings_live
        |> form("#api-key-form", api_key: %{name: "My MCP client", scope: "write"})
        |> render_submit()

      assert html =~ "Copy your new API key now"
      [api_key] = Accounts.list_api_keys_for_user(current_user)

      assert has_element?(
               settings_live,
               "button[phx-click='revoke_api_key'][phx-value-id='#{api_key.id}']",
               "Revoke"
             )

      html = render_click(settings_live, "revoke_api_key", %{"id" => to_string(api_key.id)})
      assert html =~ "API key revoked."
      assert Accounts.list_api_keys_for_user(current_user) == []
    end

    test "passwordless email users can edit their profile and request a password setup link", %{
      conn: conn
    } do
      email = unique_user_email()

      {:ok, %{user: current_user}} =
        Accounts.register_passwordless_user(
          %{"email" => email},
          %{"name" => "Passwordless User", "bio" => "Old bio"}
        )

      {:ok, current_user} = Accounts.confirm_user_email(current_user)
      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "Set a password"
      assert has_element?(settings_live, "input[name='author[name]']")

      render_submit(settings_live, "save", %{
        "author" => %{"name" => "Updated User", "bio" => "Updated bio"}
      })

      assert Authors.get_author!(current_user.author_id).name == "Updated User"

      html = render_click(settings_live, "send_password_setup_instructions")
      assert html =~ "We sent a password setup link to #{email}."
      assert Repo.get_by(UserToken, user_id: current_user.id, context: "reset_password")
    end

    test "phone verified users see a locked location and cannot submit changes to it", %{
      conn: conn
    } do
      phone_country = country_fixture(name: "Settings Phone Spain", phone_prefix: "+34")
      submitted_country = country_fixture(name: "Settings Submitted France", phone_prefix: "+33")

      current_user =
        user_fixture(
          %{},
          %{name: "Someone", bio: "Bio", twin_origin: false, country_id: submitted_country.id},
          false
        )

      {:ok, current_user} = Accounts.confirm_user_email(current_user)
      {:ok, current_user} = Accounts.update_user_phone_number(current_user, "+34611111111")
      {:ok, current_user} = Accounts.confirm_user_phone(current_user)

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "Location"
      assert html =~ "Settings Phone Spain"
      assert html =~ "Set from your verified phone number."
      refute html =~ "author[country_id]"

      render_submit(settings_live, "save", %{
        "author" => %{
          "name" => "Changed",
          "country_id" => submitted_country.id,
          "country" => submitted_country.name,
          "location" => "Submitted location"
        }
      })

      author = Authors.get_author!(current_user.author_id)
      assert author.name == "Someone"
      assert author.country_id == phone_country.id
      assert author.location == nil
    end
  end
end
