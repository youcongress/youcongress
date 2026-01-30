defmodule YouCongressWeb.XAuthControllerTest do
  use YouCongressWeb.ConnCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures

  alias YouCongress.X.XAPI
  alias YouCongress.Authors

  @x_user_data %{
    twitter_id_str: "123456789",
    twitter_username: "testuser",
    name: "Test User",
    email: "testuser@example.com",
    profile_image_url: "https://pbs.twimg.com/profile_images/123_400x400.jpg",
    description: "Test bio",
    followers_count: 100,
    friends_count: 50,
    verified: false
  }

  describe "GET /auth/x" do
    test "redirects to X authorization URL when configured", %{conn: conn} do
      Application.put_env(:you_congress, :x_client_id, "test_client_id")
      Application.put_env(:you_congress, :x_callback_url, "https://test.com/auth/x/callback")

      conn = get(conn, ~p"/auth/x")

      assert redirected_to(conn) =~ "https://twitter.com/i/oauth2/authorize"
      assert get_session(conn, :x_oauth_code_verifier)
      assert get_session(conn, :x_oauth_state)
    end

    test "redirects to login with error when not configured", %{conn: conn} do
      Application.put_env(:you_congress, :x_client_id, nil)
      Application.put_env(:you_congress, :x_callback_url, nil)

      conn = conn |> get(~p"/auth/x") |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "X authentication is not configured."
    end
  end

  describe "GET /auth/x/callback" do
    setup do
      Application.put_env(:you_congress, :x_client_id, "test_client_id")
      Application.put_env(:you_congress, :x_callback_url, "https://test.com/auth/x/callback")
      :ok
    end

    test "redirects to login when state doesn't match", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{
          x_oauth_state: "stored_state",
          x_oauth_code_verifier: "verifier"
        })
        |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "wrong_state"})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."
    end

    test "redirects to login when code_verifier is missing", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{x_oauth_state: "state"})
        |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "state"})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."
    end

    test "redirects to login when OAuth error is returned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/x/callback", %{
          "error" => "access_denied",
          "error_description" => "User denied access"
        })
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication was cancelled or denied."
    end

    test "redirects to login when callback has no recognized params", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/x/callback", %{})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."
    end

    test "redirects to login when token exchange fails", %{conn: conn} do
      with_mock XAPI, fetch_token: fn _code, _verifier, _url -> {:error, "Token error"} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/log_in"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Authentication failed. Please try again."
      end
    end

    test "redirects to login when user info fetch fails", %{conn: conn} do
      with_mock XAPI,
        fetch_token: fn _code, _verifier, _url -> {:ok, "access_token", "refresh_token"} end,
        fetch_user_info: fn _token -> {:error, "User info error"} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/log_in"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                 "Failed to retrieve your X profile. Please try again."
      end
    end

    test "creates new user and author for new X user", %{conn: conn} do
      with_mock XAPI,
        fetch_token: fn _code, _verifier, _url -> {:ok, "access_token", "refresh_token"} end,
        fetch_user_info: fn _token -> {:ok, @x_user_data} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        # Should redirect to sign_up to complete profile after successful registration
        assert redirected_to(conn) == ~p"/sign_up"

        assert get_session(conn, :user_token)

        # Verify author was created
        author = Authors.get_author_by(twitter_username: @x_user_data.twitter_username)
        assert author
        assert author.twitter_id_str == @x_user_data.twitter_id_str
        assert author.name == @x_user_data.name
      end
    end

    test "logs in existing user with linked author", %{conn: conn} do
      # Create an existing user with author
      author_attrs = %{
        name: "Existing User",
        twitter_username: @x_user_data.twitter_username,
        twitter_id_str: @x_user_data.twitter_id_str,
        twin_origin: false
      }

      user = user_fixture(%{}, author_attrs)

      with_mock XAPI,
        fetch_token: fn _code, _verifier, _url -> {:ok, "access_token", "refresh_token"} end,
        fetch_user_info: fn _token -> {:ok, @x_user_data} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/home"
        assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back!"
        assert get_session(conn, :user_token)

        # Verify the same user was logged in
        logged_in_user =
          YouCongress.Accounts.get_user_by_session_token(get_session(conn, :user_token))

        assert logged_in_user.id == user.id
      end
    end

    test "creates user for existing author without user", %{conn: conn} do
      # Create an author without a linked user
      author =
        author_fixture(
          twitter_username: @x_user_data.twitter_username,
          twitter_id_str: @x_user_data.twitter_id_str
        )

      # Verify no user is linked
      assert YouCongress.Accounts.get_user_by_author_id(author.id) == nil

      with_mock XAPI,
        fetch_token: fn _code, _verifier, _url -> {:ok, "access_token", "refresh_token"} end,
        fetch_user_info: fn _token -> {:ok, @x_user_data} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/sign_up"

        assert get_session(conn, :user_token)

        # Verify user was created and linked to existing author
        new_user = YouCongress.Accounts.get_user_by_author_id(author.id)
        assert new_user
      end
    end

    test "clears session data after callback", %{conn: conn} do
      with_mock XAPI,
        fetch_token: fn _code, _verifier, _url -> {:ok, "access_token", "refresh_token"} end,
        fetch_user_info: fn _token -> {:ok, @x_user_data} end do
        conn =
          conn
          |> init_test_session(%{
            x_oauth_state: "valid_state",
            x_oauth_code_verifier: "valid_verifier"
          })
          |> get(~p"/auth/x/callback", %{"code" => "auth_code", "state" => "valid_state"})

        # OAuth session data should be cleared
        refute get_session(conn, :x_oauth_code_verifier)
        refute get_session(conn, :x_oauth_state)
      end
    end
  end
end
