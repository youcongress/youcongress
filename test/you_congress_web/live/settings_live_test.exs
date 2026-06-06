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
        "author" => %{"name" => "Someone", "country_id" => country.id}
      })

      author = Authors.get_author!(current_user.author_id)
      assert author.country_id == country.id
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
      assert author.name == "Changed"
      assert author.country_id == phone_country.id
      assert author.location == nil
    end
  end
end
