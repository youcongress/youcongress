defmodule YouCongressWeb.XAuthController do
  use YouCongressWeb, :controller

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.X.XAPI
  alias YouCongress.Track
  alias YouCongressWeb.UserAuth

  @doc """
  Initiates the X OAuth flow by redirecting to X's authorization URL.
  Stores the code_verifier and state in the session for verification in the callback.
  """
  def request(conn, _params) do
    client_id = Application.get_env(:you_congress, :x_client_id)
    callback_url = Application.get_env(:you_congress, :x_callback_url)

    if is_nil(client_id) or is_nil(callback_url) do
      conn
      |> put_flash(:error, "X authentication is not configured.")
      |> redirect(to: ~p"/log_in")
    else
      {authorize_url, code_verifier, state} = XAPI.generate_authorize_url(client_id, callback_url)

      conn
      |> put_session(:x_oauth_code_verifier, code_verifier)
      |> put_session(:x_oauth_state, state)
      |> redirect(external: authorize_url)
    end
  end

  @doc """
  Handles the OAuth callback from X.
  Exchanges the authorization code for tokens, fetches user info,
  and either logs in an existing user or creates a new one.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :x_oauth_state)
    code_verifier = get_session(conn, :x_oauth_code_verifier)
    callback_url = Application.get_env(:you_congress, :x_callback_url)

    conn =
      conn
      |> delete_session(:x_oauth_code_verifier)
      |> delete_session(:x_oauth_state)

    cond do
      is_nil(stored_state) or state != stored_state ->
        Logger.warning("X OAuth state mismatch: expected=#{stored_state}, got=#{state}")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/log_in")

      is_nil(code_verifier) ->
        Logger.warning("X OAuth code_verifier missing from session")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/log_in")

      true ->
        handle_token_exchange(conn, code, code_verifier, callback_url)
    end
  end

  def callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.warning("X OAuth error: #{error} - #{description}")

    conn
    |> put_flash(:error, "Authentication was cancelled or denied.")
    |> redirect(to: ~p"/log_in")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/log_in")
  end

  defp handle_token_exchange(conn, code, code_verifier, callback_url) do
    case XAPI.fetch_token(code, code_verifier, callback_url) do
      {:ok, access_token, _refresh_token} ->
        handle_user_info(conn, access_token)

      {:error, reason} ->
        Logger.error("X token exchange failed: #{reason}")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_user_info(conn, access_token) do
    case XAPI.fetch_user_info(access_token) do
      {:ok, x_user_data} ->
        handle_user_lookup_or_create(conn, x_user_data)

      {:error, reason} ->
        Logger.error("X user info fetch failed: #{reason}")

        conn
        |> put_flash(:error, "Failed to retrieve your X profile. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_user_lookup_or_create(conn, x_user_data) do
    %{twitter_id_str: twitter_id_str, twitter_username: twitter_username} = x_user_data

    # Look for existing author by twitter_id_str or twitter_username
    case Authors.get_author_by_twitter_id_str_or_username(twitter_id_str, twitter_username) do
      nil ->
        # No existing author - create new author and user
        create_new_author_and_user(conn, x_user_data)

      author ->
        # Author exists - check if user is linked
        case Accounts.get_user_by_author_id(author.id) do
          nil ->
            # Author exists but no user linked - create user and link to author
            create_user_for_existing_author(conn, author, x_user_data)

          user ->
            # Both author and user exist - log them in
            log_in_existing_user(conn, user, author, x_user_data)
        end
    end
  end

  defp create_new_author_and_user(conn, x_user_data) do
    author_attrs = build_author_attrs(x_user_data)
    # Don't set email here - user will provide it in the profile completion step
    user_attrs = %{}

    case Accounts.x_register_user(user_attrs, author_attrs) do
      {:ok, %{user: user}} ->
        Track.event("Register via X", user)

        # Log in the user and redirect to sign_up to complete profile (add email)
        conn
        |> put_session(:user_return_to, ~p"/sign_up")
        |> UserAuth.log_in_user(user)

      {:error, :author, changeset, _} ->
        Logger.error("Failed to create author for X signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")

      {:error, :user, changeset, _} ->
        Logger.error("Failed to create user for X signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp create_user_for_existing_author(conn, author, x_user_data) do
    author_update_attrs = build_author_attrs(x_user_data)
    # Don't set email here - user will provide it in the profile completion step
    user_attrs = %{}

    case Accounts.x_register_user_with_existing_author(user_attrs, author, author_update_attrs) do
      {:ok, %{user: user}} ->
        Track.event("Register via X (existing author)", user)

        # Log in the user and redirect to sign_up to complete profile (add email)
        conn
        |> put_session(:user_return_to, ~p"/sign_up")
        |> UserAuth.log_in_user(user)

      {:error, :author, changeset, _} ->
        Logger.error("Failed to update author for X signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")

      {:error, :user, changeset, _} ->
        Logger.error("Failed to create user for X signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp log_in_existing_user(conn, user, author, x_user_data) do
    # Update author with latest X profile data
    author_update_attrs = build_author_attrs(x_user_data)
    Authors.update_author(author, author_update_attrs)

    Track.event("Login via X", user)

    # Check if user needs to complete profile (no confirmed email)
    if user.email_confirmed_at do
      conn
      |> UserAuth.log_in_user(user)
    else
      conn
      |> put_session(:user_return_to, ~p"/sign_up")
      |> UserAuth.log_in_user(user)
    end
  end

  defp build_author_attrs(x_user_data) do
    %{
      twitter_id_str: x_user_data.twitter_id_str,
      twitter_username: x_user_data.twitter_username,
      name: x_user_data.name,
      profile_image_url: x_user_data.profile_image_url,
      description: x_user_data.description,
      followers_count: x_user_data.followers_count,
      friends_count: x_user_data.friends_count,
      verified: x_user_data.verified
    }
  end
end
