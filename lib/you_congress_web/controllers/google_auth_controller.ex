defmodule YouCongressWeb.GoogleAuthController do
  use YouCongressWeb, :controller

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Google.GoogleAPI
  alias YouCongress.Track
  alias YouCongressWeb.UserAuth

  @doc """
  Initiates the Google OAuth flow by redirecting to Google's authorization URL.
  Stores the state in the session for verification in the callback.
  """
  def request(conn, _params) do
    client_id = Application.get_env(:you_congress, :google_client_id)
    callback_url = Application.get_env(:you_congress, :google_callback_url)

    if is_nil(client_id) or is_nil(callback_url) do
      conn
      |> put_flash(:error, "Google authentication is not configured.")
      |> redirect(to: ~p"/log_in")
    else
      {authorize_url, state} = GoogleAPI.generate_authorize_url(client_id, callback_url)

      conn
      |> put_session(:google_oauth_state, state)
      |> redirect(external: authorize_url)
    end
  end

  @doc """
  Handles the OAuth callback from Google.
  Exchanges the authorization code for tokens, fetches user info,
  and either logs in an existing user or creates a new one.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    stored_state = get_session(conn, :google_oauth_state)
    callback_url = Application.get_env(:you_congress, :google_callback_url)

    conn = delete_session(conn, :google_oauth_state)

    cond do
      is_nil(stored_state) or state != stored_state ->
        Logger.warning("Google OAuth state mismatch: expected=#{stored_state}, got=#{state}")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/log_in")

      true ->
        handle_token_exchange(conn, code, callback_url)
    end
  end

  def callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.warning("Google OAuth error: #{error} - #{description}")

    conn
    |> put_flash(:error, "Authentication was cancelled or denied.")
    |> redirect(to: ~p"/log_in")
  end

  def callback(conn, %{"error" => error}) do
    Logger.warning("Google OAuth error: #{error}")

    conn
    |> put_flash(:error, "Authentication was cancelled or denied.")
    |> redirect(to: ~p"/log_in")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/log_in")
  end

  defp handle_token_exchange(conn, code, callback_url) do
    case GoogleAPI.fetch_token(code, callback_url) do
      {:ok, access_token} ->
        handle_user_info(conn, access_token)

      {:error, reason} ->
        Logger.error("Google token exchange failed: #{reason}")

        conn
        |> put_flash(:error, "Authentication failed. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_user_info(conn, access_token) do
    case GoogleAPI.fetch_user_info(access_token) do
      {:ok, google_user_data} ->
        handle_user_lookup_or_create(conn, google_user_data)

      {:error, reason} ->
        Logger.error("Google user info fetch failed: #{reason}")

        conn
        |> put_flash(:error, "Failed to retrieve your Google profile. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_user_lookup_or_create(conn, google_user_data) do
    %{google_id: google_id, email: email} = google_user_data

    # Look for existing author by google_id
    case Authors.get_author_by_google_id(google_id) do
      nil ->
        # No author with google_id - check if user exists with this email
        # (e.g., user signed up with X using the same email)
        case email && Accounts.get_user_by_email(email) do
          nil ->
            # No existing user - create new author and user
            create_new_author_and_user(conn, google_user_data)

          user ->
            # User exists with this email - link Google account to their author
            link_google_to_existing_user(conn, user, google_user_data)
        end

      author ->
        # Author exists with google_id - check if user is linked
        case Accounts.get_user_by_author_id(author.id) do
          nil ->
            # Author exists but no user linked - create user and link to author
            create_user_for_existing_author(conn, author, google_user_data)

          user ->
            # Both author and user exist - log them in
            log_in_existing_user(conn, user, author, google_user_data)
        end
    end
  end

  defp link_google_to_existing_user(conn, user, google_user_data) do
    # Load the author if not already loaded
    user = YouCongress.Repo.preload(user, :author)
    author = user.author

    # Update the author with Google ID
    author_update_attrs = build_author_attrs(google_user_data)

    case Authors.update_author(author, author_update_attrs) do
      {:ok, _updated_author} ->
        Track.event("Login via Google (linked account)", user)

        # If user's email isn't confirmed but Google's is verified, confirm it
        user =
          if is_nil(user.email_confirmed_at) && google_user_data.email_verified do
            case Accounts.confirm_user_email(user) do
              {:ok, confirmed_user} -> confirmed_user
              _ -> user
            end
          else
            user
          end

        if user.email_confirmed_at do
          conn
          |> put_flash(:info, "Welcome back! Your Google account has been linked.")
          |> UserAuth.log_in_user(user)
        else
          conn
          |> put_flash(:info, "Welcome back! Your Google account has been linked.")
          |> put_session(:user_return_to, ~p"/sign_up")
          |> UserAuth.log_in_user(user)
        end

      {:error, changeset} ->
        Logger.error("Failed to link Google account: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to link Google account. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp create_new_author_and_user(conn, google_user_data) do
    author_attrs = build_author_attrs(google_user_data)
    user_attrs = build_user_attrs(google_user_data)

    case Accounts.google_register_user(user_attrs, author_attrs) do
      {:ok, %{user: user}} ->
        Track.event("Register via Google", user)

        # If Google provided a verified email, auto-confirm it
        user =
          if google_user_data.email_verified && user.email do
            case Accounts.confirm_user_email(user) do
              {:ok, confirmed_user} -> confirmed_user
              _ -> user
            end
          else
            user
          end

        # Google provides email, so we may skip the profile completion step
        # but still need phone verification
        if user.email_confirmed_at do
          conn
          |> put_session(:user_return_to, ~p"/sign_up")
          |> UserAuth.log_in_user(user)
        else
          conn
          |> put_session(:user_return_to, ~p"/sign_up")
          |> UserAuth.log_in_user(user)
        end

      {:error, :author, changeset, _} ->
        Logger.error("Failed to create author for Google signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")

      {:error, :user, changeset, _} ->
        Logger.error("Failed to create user for Google signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp create_user_for_existing_author(conn, author, google_user_data) do
    author_update_attrs = build_author_attrs(google_user_data)
    user_attrs = build_user_attrs(google_user_data)

    case Accounts.google_register_user_with_existing_author(
           user_attrs,
           author,
           author_update_attrs
         ) do
      {:ok, %{user: user}} ->
        Track.event("Register via Google (existing author)", user)

        # If Google provided a verified email, auto-confirm it
        user =
          if google_user_data.email_verified && user.email do
            case Accounts.confirm_user_email(user) do
              {:ok, confirmed_user} -> confirmed_user
              _ -> user
            end
          else
            user
          end

        conn
        |> put_session(:user_return_to, ~p"/sign_up")
        |> UserAuth.log_in_user(user)

      {:error, :author, changeset, _} ->
        Logger.error("Failed to update author for Google signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")

      {:error, :user, changeset, _} ->
        Logger.error("Failed to create user for Google signup: #{inspect(changeset.errors)}")

        conn
        |> put_flash(:error, "Failed to create account. Please try again.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp log_in_existing_user(conn, user, author, google_user_data) do
    # Update author with latest Google profile data
    author_update_attrs = build_author_attrs(google_user_data)
    Authors.update_author(author, author_update_attrs)

    Track.event("Login via Google", user)

    # Check if user needs to complete profile (no confirmed email or phone)
    if user.email_confirmed_at do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user)
    else
      conn
      |> put_flash(:info, "Welcome back! Please complete your profile.")
      |> put_session(:user_return_to, ~p"/sign_up")
      |> UserAuth.log_in_user(user)
    end
  end

  defp build_author_attrs(google_user_data) do
    %{
      google_id: google_user_data.google_id,
      name: google_user_data.name,
      profile_image_url: google_user_data.profile_image_url
    }
  end

  defp build_user_attrs(google_user_data) do
    if google_user_data.email do
      %{email: google_user_data.email}
    else
      %{}
    end
  end
end
