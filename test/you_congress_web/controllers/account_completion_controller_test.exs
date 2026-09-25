defmodule YouCongressWeb.AccountCompletionControllerTest do
  use YouCongressWeb.ConnCase

  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  setup %{conn: conn} do
    user = user_fixture(%{}, %{name: "Incomplete account", twin_origin: false}, false)
    {:ok, user} = Accounts.confirm_user_email(user)

    %{conn: log_in_user(conn, user), user: user}
  end

  test "phone and newsletter prompts are shown sequentially and dismissed independently", %{
    conn: conn,
    user: user
  } do
    phone_html = conn |> get(~p"/about") |> html_response(200)
    assert phone_html =~ "Optional · 1/2"
    assert phone_html =~ "Verify your phone"
    refute phone_html =~ "Get occasional YouCongress updates"

    conn = post(conn, ~p"/account-completion/dismiss-phone?return_to=/about")
    assert redirected_to(conn) == ~p"/about"

    user = Accounts.get_user!(user.id)
    assert user.phone_verification_prompt_dismissed_at
    refute user.newsletter_subscription_prompt_dismissed_at

    conn = recycle(conn)
    newsletter_html = conn |> get(~p"/about") |> html_response(200)
    assert newsletter_html =~ "Optional · 2/2"
    assert newsletter_html =~ "Get occasional YouCongress updates"
    assert newsletter_html =~ "Subscribe"
    refute newsletter_html =~ "Verify your phone"

    conn = post(conn, ~p"/account-completion/dismiss-newsletter?return_to=/about")
    assert redirected_to(conn) == ~p"/about"

    user = Accounts.get_user!(user.id)
    assert user.newsletter_subscription_prompt_dismissed_at
    conn = recycle(conn)
    refute conn |> get(~p"/about") |> html_response(200) =~ "account-completion-banner"
  end

  test "newsletter subscription is stored and returns to the current page", %{
    conn: conn,
    user: user
  } do
    refute user.newsletter
    {:ok, _user} = Accounts.dismiss_phone_verification_prompt(user)

    conn = post(conn, ~p"/account-completion/newsletter?return_to=/settings")

    assert redirected_to(conn) == ~p"/settings"
    assert Accounts.get_user!(user.id).newsletter
  end

  test "external return paths are rejected", %{conn: conn} do
    conn = post(conn, ~p"/account-completion/dismiss-phone?return_to=https://example.com")
    assert redirected_to(conn) == ~p"/"
  end
end
