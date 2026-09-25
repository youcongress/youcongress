defmodule YouCongressWeb.AccountCompletionControllerTest do
  use YouCongressWeb.ConnCase

  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  setup %{conn: conn} do
    user = user_fixture(%{}, %{name: "Incomplete account", twin_origin: false}, false)
    {:ok, user} = Accounts.confirm_user_email(user)

    %{conn: log_in_user(conn, user), user: user}
  end

  test "the optional account reminder is shown until it is dismissed", %{
    conn: conn,
    user: user
  } do
    assert conn |> get(~p"/about") |> html_response(200) =~ "account-completion-banner"

    {:ok, _user} = Accounts.dismiss_account_completion_banner(user)

    refute conn |> get(~p"/about") |> html_response(200) =~ "account-completion-banner"
  end

  test "dismissal is stored on the account and returns to the current page", %{
    conn: conn,
    user: user
  } do
    conn = post(conn, ~p"/account-completion/dismiss?return_to=/about")

    assert redirected_to(conn) == ~p"/about"
    assert Accounts.get_user!(user.id).account_completion_banner_dismissed_at
  end

  test "newsletter subscription is stored and returns to the current page", %{
    conn: conn,
    user: user
  } do
    refute user.newsletter

    conn = post(conn, ~p"/account-completion/newsletter?return_to=/settings")

    assert redirected_to(conn) == ~p"/settings"
    assert Accounts.get_user!(user.id).newsletter
  end

  test "external return paths are rejected", %{conn: conn} do
    conn = post(conn, ~p"/account-completion/dismiss?return_to=https://example.com")
    assert redirected_to(conn) == ~p"/"
  end
end
