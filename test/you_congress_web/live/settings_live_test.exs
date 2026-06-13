defmodule YouCongressWeb.SettingsLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.CountriesFixtures

  alias YouCongress.{Accounts, Authors}

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
      {:ok, _settings_live, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
      assert html =~ "Name: Someone"
    end

    test "users without a verified phone see a link to verify it", %{conn: conn} do
      current_user = user_fixture(%{}, %{name: "Someone", twin_origin: false}, false)
      {:ok, current_user} = Accounts.confirm_user_email(current_user)

      conn = log_in_user(conn, current_user)
      {:ok, settings_live, html} = live(conn, ~p"/settings")

      assert html =~ "Verify with phone"

      assert settings_live
             |> element("a", "Verify with phone")
             |> render() =~ ~p"/sign_up"
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
