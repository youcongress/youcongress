defmodule YouCongressWeb.GoogleAuthControllerTest do
  use YouCongressWeb.ConnCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import ExUnit.CaptureLog

  alias YouCongress.Google.GoogleAPI
  alias YouCongress.Authors

  @google_user_data %{
    google_id: "123456789",
    email: "testuser@gmail.com",
    name: "Test User",
    profile_image_url: "https://lh3.googleusercontent.com/a/photo.jpg",
    email_verified: true
  }

  describe "GET /auth/google" do
    test "redirects to Google authorization URL when configured", %{conn: conn} do
      Application.put_env(:you_congress, :google_client_id, "test_client_id")

      Application.put_env(
        :you_congress,
        :google_callback_url,
        "https://test.com/auth/google/callback"
      )

      conn = get(conn, ~p"/auth/google")

      assert redirected_to(conn) =~ "https://accounts.google.com/o/oauth2/v2/auth"
      assert get_session(conn, :google_oauth_state)
    end

    test "redirects to login with error when not configured", %{conn: conn} do
      Application.put_env(:you_congress, :google_client_id, nil)
      Application.put_env(:you_congress, :google_callback_url, nil)

      conn = conn |> get(~p"/auth/google") |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Google authentication is not configured."
    end
  end

  describe "GET /auth/google/callback" do
    setup do
      Application.put_env(:you_congress, :google_client_id, "test_client_id")
      Application.put_env(:you_congress, :google_client_secret, "test_client_secret")

      Application.put_env(
        :you_congress,
        :google_callback_url,
        "https://test.com/auth/google/callback"
      )

      :ok
    end

    test "redirects to login when state doesn't match", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{google_oauth_state: "stored_state"})
        |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "wrong_state"})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."
    end

    test "redirects to login when OAuth error is returned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/google/callback", %{
          "error" => "access_denied",
          "error_description" => "User denied access"
        })
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication was cancelled or denied."
    end

    test "redirects to login when OAuth error without description is returned", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/google/callback", %{"error" => "access_denied"})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication was cancelled or denied."
    end

    test "redirects to login when callback has no recognized params", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> get(~p"/auth/google/callback", %{})
        |> fetch_flash()

      assert redirected_to(conn) == ~p"/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed. Please try again."
    end

    test "redirects to login when token exchange fails", %{conn: conn} do
      with_mock GoogleAPI, fetch_token: fn _code, _url -> {:error, "Token error"} end do
        capture_log(fn ->
          conn =
            conn
            |> init_test_session(%{google_oauth_state: "valid_state"})
            |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
            |> fetch_flash()

          assert redirected_to(conn) == ~p"/log_in"

          assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                   "Authentication failed. Please try again."
        end)
      end
    end

    test "redirects to login when user info fetch fails", %{conn: conn} do
      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:error, "User info error"} end do
        capture_log(fn ->
          conn =
            conn
            |> init_test_session(%{google_oauth_state: "valid_state"})
            |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
            |> fetch_flash()

          assert redirected_to(conn) == ~p"/log_in"

          assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
                   "Failed to retrieve your Google profile. Please try again."
        end)
      end
    end

    test "creates new user and author for new Google user", %{conn: conn} do
      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:ok, @google_user_data} end do
        conn =
          conn
          |> init_test_session(%{google_oauth_state: "valid_state"})
          |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        # Should redirect to sign_up to complete profile after successful registration
        assert redirected_to(conn) == ~p"/sign_up"

        assert get_session(conn, :user_token)

        # Verify author was created
        author = Authors.get_author_by_google_id(@google_user_data.google_id)
        assert author
        assert author.name == @google_user_data.name
      end
    end

    test "logs in existing user with linked author", %{conn: conn} do
      # Create an existing user with author
      author_attrs = %{
        name: "Existing User",
        google_id: @google_user_data.google_id,
        twin_origin: false
      }

      user = google_user_fixture(%{email: @google_user_data.email}, author_attrs)

      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:ok, @google_user_data} end do
        conn =
          conn
          |> init_test_session(%{google_oauth_state: "valid_state"})
          |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/home"
        assert get_session(conn, :user_token)

        # Verify the same user was logged in
        logged_in_user =
          YouCongress.Accounts.get_user_by_session_token(get_session(conn, :user_token))

        assert logged_in_user.id == user.id
      end
    end

    test "creates user for existing author without user", %{conn: conn} do
      # Create an author without a linked user
      author = author_fixture(google_id: @google_user_data.google_id)

      # Verify no user is linked
      assert YouCongress.Accounts.get_user_by_author_id(author.id) == nil

      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:ok, @google_user_data} end do
        conn =
          conn
          |> init_test_session(%{google_oauth_state: "valid_state"})
          |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/sign_up"

        assert get_session(conn, :user_token)

        # Verify user was created and linked to existing author
        new_user = YouCongress.Accounts.get_user_by_author_id(author.id)
        assert new_user
      end
    end

    test "clears session data after callback", %{conn: conn} do
      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:ok, @google_user_data} end do
        conn =
          conn
          |> init_test_session(%{google_oauth_state: "valid_state"})
          |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})

        # OAuth session data should be cleared
        refute get_session(conn, :google_oauth_state)
      end
    end

    test "links Google account to existing X user with same email", %{conn: conn} do
      # Create a user via X (twitter) with the same email as the Google user
      x_author_attrs = %{
        name: "X User",
        twitter_username: "xuser",
        twitter_id_str: "twitter_123",
        twin_origin: false
      }

      x_user = user_fixture(%{email: @google_user_data.email}, x_author_attrs)

      # Verify the author doesn't have google_id yet
      x_user_author = YouCongress.Repo.preload(x_user, :author).author
      assert is_nil(x_user_author.google_id)

      with_mock GoogleAPI,
        fetch_token: fn _code, _url -> {:ok, "access_token"} end,
        fetch_user_info: fn _token -> {:ok, @google_user_data} end do
        conn =
          conn
          |> init_test_session(%{google_oauth_state: "valid_state"})
          |> get(~p"/auth/google/callback", %{"code" => "auth_code", "state" => "valid_state"})
          |> fetch_flash()

        assert redirected_to(conn) == ~p"/home"

        assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
                 "Welcome back! Your Google account has been linked."

        assert get_session(conn, :user_token)

        # Verify the same user was logged in
        logged_in_user =
          YouCongress.Accounts.get_user_by_session_token(get_session(conn, :user_token))

        assert logged_in_user.id == x_user.id

        # Verify Google ID was linked to the existing author
        updated_author = YouCongress.Authors.get_author!(x_user_author.id)
        assert updated_author.google_id == @google_user_data.google_id
      end
    end
  end
end
