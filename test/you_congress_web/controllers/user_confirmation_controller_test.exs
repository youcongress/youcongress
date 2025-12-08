defmodule YouCongressWeb.UserConfirmationControllerTest do
  use YouCongressWeb.ConnCase, async: true

  alias YouCongress.Accounts
  import YouCongress.AccountsFixtures
  import YouCongress.ManifestosFixtures
  import Swoosh.TestAssertions

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/confirm" do
    test "confirms the user and signs manifesto if slug is present", %{conn: conn} do
      user = user_fixture(%{}, nil, false)
      Accounts.deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))

      email =
        receive do
          {:email, email} -> email
        after
          100 -> flunk("No email received")
        end

      assert Enum.any?(email.to, fn {_, e} -> e == user.email end)

      # Extract token from the link in the email body
      # The link format depends on the email template, but search for /users/confirm/TOKEN
      # If html body or text body
      body = email.html_body || email.text_body
      [_, token] = Regex.run(~r/users\/confirm\/([^\s"&?]+)/, body)

      manifesto = manifesto_fixture()

      conn = get(conn, ~p"/users/confirm/#{token}?manifesto_slug=#{manifesto.slug}")

      assert redirected_to(conn) == ~p"/m/#{manifesto.slug}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "You have successfully signed the manifesto"

      # Reload user and manifesto to check signature
      user = Accounts.get_user!(user.id)
      assert user.email_confirmed_at

      assert YouCongress.Manifestos.signed?(manifesto, user)
    end
  end
end
