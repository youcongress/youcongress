defmodule YouCongressWeb.AiWelcomeLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest

  alias YouCongress.AccountsFixtures
  alias YouCongress.Repo

  test "confirms the interest and offers the invite link and exploring YouCongress", %{conn: conn} do
    user = AccountsFixtures.user_fixture() |> Repo.preload(:author)

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/ai-welcome")

    assert html =~ "Private preview"
    assert html =~ "before Tuesday, September 8"
    assert html =~ "Personal invitations are welcome"
    assert html =~ "Your interest is registered"
    assert html =~ "Invite a friend"
    assert html =~ "#{YouCongressWeb.Endpoint.url()}/ai"
    assert html =~ "Explore YouCongress"
  end

  test "is reachable when logged out", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/ai-welcome")

    assert html =~ "Your interest is registered"
  end
end
