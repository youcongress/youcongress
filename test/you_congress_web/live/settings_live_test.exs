defmodule YouCongressWeb.SettingsLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures

  defp create_user(_) do
    current_user = user_fixture(%{}, %{name: "Someone"})
    %{current_user: current_user}
  end

  describe "Settings" do
    setup [:create_user]

    test "Non-logged visitors can't load the page", %{conn: conn} do
      {:error,
       {:redirect, %{flash: %{"error" => "You must log in to access this page."}, to: "/"}}} =
        live(conn, ~p"/settings")
    end

    test "Logged users can load the page", %{conn: conn, current_user: current_user} do
      conn = log_in_user(conn, current_user)
      {:ok, _settings_live, html} = live(conn, ~p"/settings")
      assert html =~ "Settings"
      assert html =~ "Name: Someone"
    end
  end
end
