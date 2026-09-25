defmodule YouCongressWeb.UserRegistrationLiveTest do
  use YouCongressWeb.ConnCase

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import YouCongress.AccountsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Accounts.UserToken
  alias YouCongress.PendingActions.PendingRegistrationAction
  alias YouCongress.Repo
  alias YouCongress.Votes

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sign_up")

      assert html =~ "Register for an account"
      assert html =~ "Log in"
      assert html =~ "Continue with email"
      refute html =~ ~s(type="password")
    end

    test "creates a passwordless account and emails a magic link", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, _html} = live(conn, ~p"/sign_up?return_to=/settings")

      html =
        lv
        |> form("#registration_form", user: %{name: "New User", email: email})
        |> render_submit()

      assert html =~ "Check your email"
      assert html =~ "expires in 15 minutes"

      user = Accounts.get_user_by_email(email)
      assert user
      assert user.hashed_password == nil
      assert user.email_confirmed_at == nil
      assert Repo.get_by(UserToken, user_id: user.id, context: "magic_login")

      assert_email_sent(fn email_message ->
        assert email_message.subject == "Confirm your YouCongress email"
        assert email_message.text_body =~ "Confirm your email"
        assert email_message.html_body =~ ">Confirm your email</a>"
      end)
    end

    test "an existing email receives the same registration response without disclosure", %{
      conn: conn
    } do
      existing_user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/sign_up")

      html =
        lv
        |> form("#registration_form",
          user: %{name: "Different Name", email: existing_user.email}
        )
        |> render_submit()

      assert html =~ "Check your email"
      refute html =~ "has already been taken"
      assert Repo.get_by(UserToken, user_id: existing_user.id, context: "magic_login")

      assert_email_sent(fn email_message ->
        assert email_message.to == [{"", existing_user.email}]
        assert email_message.subject == "Confirm your YouCongress email"
      end)
    end

    test "defers pre-registration votes until the magic link confirms the email", %{
      conn: conn
    } do
      email = unique_user_email()
      statement = statement_fixture()

      pending_actions =
        Jason.encode!(%{
          delegate_ids: [],
          votes: %{
            statement.id => %{statement_id: statement.id, answer: "for"}
          }
        })

      {:ok, lv, _html} = live(conn, ~p"/sign_up?pending_actions=#{pending_actions}")

      lv
      |> form("#registration_form", user: %{name: "Pending Voter", email: email})
      |> render_submit()

      user = Accounts.get_user_by_email(email)
      refute user.email_confirmed_at
      refute Votes.get_by(%{author_id: user.author_id, statement_id: statement.id})
      assert Repo.get_by(PendingRegistrationAction, user_id: user.id)

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_registration_magic_link_instructions(user, url_fun)
        end)

      assert {:ok, confirmed_user} = Accounts.consume_magic_login_token(token)
      assert confirmed_user.email_confirmed_at
      assert Votes.get_by(%{author_id: user.author_id, statement_id: statement.id}).answer == :for
      refute Repo.get_by(PendingRegistrationAction, user_id: user.id)
    end

    test "subscription page creates a newsletter subscriber", %{conn: conn} do
      email = unique_user_email()
      {:ok, lv, html} = live(conn, ~p"/subscribe")

      assert html =~
               "Subscribe to YouCongress news on AI governance, safety, and its impact on jobs"

      assert html =~ "Subscribe"
      refute html =~ "Sign up with Google"

      html =
        lv
        |> form("#registration_form", user: %{name: "News Reader", email: email})
        |> render_submit()

      assert html =~ "Check your email"

      user = Accounts.get_user_by_email(email)
      assert user.newsletter
      assert Repo.get_by(UserToken, user_id: user.id, context: "magic_login")
    end

    test "preserves return_to in OAuth links", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/sign_up?return_to=/p/test-statement")

      assert html =~ ~s(href="/auth/google?return_to=%2Fp%2Ftest-statement")
    end

    test "a user with a confirmed email returns directly to what they were doing", %{conn: conn} do
      user = user_fixture(%{}, %{name: "New user", twin_origin: false}, false)
      {:ok, user} = Accounts.confirm_user_email(user)
      conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/p/test-statement"}}} =
               live(conn, ~p"/sign_up?return_to=/p/test-statement")
    end

    test "phone verification remains available when explicitly requested", %{conn: conn} do
      user = user_fixture(%{}, %{name: "New user", twin_origin: false}, false)
      {:ok, user} = Accounts.confirm_user_email(user)
      conn = log_in_user(conn, user)

      {:ok, lv, html} = live(conn, ~p"/sign_up?phone=true&return_to=/settings")

      assert html =~ "Enter your mobile phone number"
      assert html =~ "Maybe later"

      render_click(lv, "skip_phone")
      assert Accounts.get_user!(user.id).phone_verification_prompt_dismissed_at
    end

    test "email-code attempts remain limited across LiveView remounts", %{conn: conn} do
      user = user_fixture(%{}, %{name: "Unconfirmed user"}, false)

      {:ok, email} =
        Accounts.deliver_user_confirmation_instructions(
          user,
          &"https://example.com/users/confirm/#{&1}"
        )

      [_, valid_code] =
        Regex.run(~r/confirmation code is: (\d{6})/, email.text_body)

      invalid_code = if valid_code == "000000", do: "111111", else: "000000"

      conn = log_in_user(conn, user)

      for _ <- 1..5 do
        {:ok, lv, html} = live(conn, ~p"/sign_up")
        assert html =~ "Enter your confirmation code"

        lv
        |> form("#email_verification_form", user: %{email_verification_code: invalid_code})
        |> render_submit()
      end

      {:ok, lv, _html} = live(conn, ~p"/sign_up")

      html =
        lv
        |> form("#email_verification_form", user: %{email_verification_code: valid_code})
        |> render_submit()

      assert html =~ "Enter your confirmation code"
      refute Accounts.get_user!(user.id).email_confirmed_at
    end
  end
end
