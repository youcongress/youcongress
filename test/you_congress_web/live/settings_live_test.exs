defmodule YouCongressWeb.SettingsLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Votes

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

    test "Disable AI-generated content deletes AI-gen content from user", %{
      conn: conn,
      current_user: current_user
    } do
      conn = log_in_user(conn, current_user)
      someone_else = user_fixture()

      #  Create some AI-generated votes (twin: true)
      vote1 = vote_fixture(%{author_id: current_user.author_id, twin: true})
      vote2 = vote_fixture(%{author_id: current_user.author_id, twin: true})
      vote3 = vote_fixture(%{author_id: someone_else.author_id, twin: true})

      {:ok, settings_live, _html} = live(conn, ~p"/settings")

      # Uncheck the AI-generated content setting
      settings_live
      |> form("#author-form", %{"author[twin_enabled]" => false})
      |> render_change()

      # Submit the form
      settings_live
      |> form("#author-form", %{"author[twin_enabled]" => false})
      |> render_submit()

      html = render(settings_live)

      assert html =~ "Settings updated successfully"

      # Check that the votes were deleted
      assert Votes.get_vote(vote1.id) == nil
      assert Votes.get_vote(vote2.id) == nil

      # Check that the vote from someone else was not deleted
      assert Votes.get_vote(vote3.id) != nil
      assert Votes.get_vote(vote3.id) == vote3
    end
  end
end
