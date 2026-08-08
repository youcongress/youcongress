defmodule YouCongressWeb.AiWelcomeLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

  alias YouCongress.Accounts.User
  alias YouCongress.AccountsFixtures
  alias YouCongress.Repo

  test "confirms the interest and offers the invite link and exploring YouCongress", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    user =
      user
      |> User.sign_up_context_changeset(%{
        sign_up_context: %{"contribution_areas" => ["platform", "outreach"]}
      })
      |> Repo.update!()
      |> Repo.preload(:author)

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/ai-welcome")

    assert html =~ "Private preview"
    assert html =~ "before Tuesday, September 8"
    assert html =~ "Personal invitations are welcome"
    assert html =~ "You&#39;re part of the mission"
    assert html =~ "What happens next"
    assert html =~ "Improve YouCongress"
    assert html =~ "Reach policymakers and civic organizations"
    assert html =~ "Invite a friend"
    assert html =~ "#{YouCongressWeb.Endpoint.url()}/ai"
    assert html =~ "Explore proposals and evidence"
  end

  test "is reachable when logged out", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/ai-welcome")

    assert html =~ "You&#39;re part of the mission"
    assert html =~ "Each group starts with a clear task and a useful output"
  end
end
