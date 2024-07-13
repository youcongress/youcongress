defmodule YouCongressWeb.TwitterLogInController do
  use YouCongressWeb, :controller

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Track

  def log_in(conn, _params) do
    base_url = Application.get_env(:you_congress, :base_url)
    token = ExTwitter.request_token(base_url <> "/twitter-callback")

    {:ok, authenticate_url} = ExTwitter.authenticate_url(token.oauth_token)
    redirect(conn, external: authenticate_url)
  end

  def callback(conn, %{"oauth_token" => oauth_token, "oauth_verifier" => oauth_verifier}) do
    case YouCongressWeb.TwitterLogInController.get_callback_data(oauth_token, oauth_verifier) do
      {:ok, data} ->
        author_attrs = %{
          twitter_username: data.screen_name,
          twitter_id_str: data.id_str,
          name: data.name,
          profile_image_url: data.profile_image_url_https,
          description: data.description,
          location: data.location,
          followers_count: data.followers_count,
          friends_count: data.friends_count,
          verified: data.verified
        }

        email = data.raw_data.email

        user = Accounts.get_user_by_twitter_id_str_or_username(data.id_str, data.screen_name)
        create_or_log_in_user(user, email, author_attrs, conn)

      {:error, error} ->
        Logger.error("Error getting Twitter data: #{inspect(error)}")

        conn
        |> put_flash(:error, "There was an error.")
        |> redirect(to: "/")
    end
  end

  def get_callback_data(oauth_token, oauth_verifier) do
    case ExTwitter.access_token(oauth_verifier, oauth_token) do
      {:ok, access_token} ->
        ExTwitter.configure(
          consumer_key: System.get_env("TWITTER_CONSUMER_KEY"),
          consumer_secret: System.get_env("TWITTER_CONSUMER_SECRET"),
          access_token: access_token.oauth_token,
          access_token_secret: access_token.oauth_token_secret
        )

        data = ExTwitter.verify_credentials(include_email: true)

        {:ok, data}

      {:error, error} ->
        {:error, error}
    end
  end

  defp create_or_log_in_user(nil, email, author_attrs, conn) do
    user_attrs = %{"role" => "user", "email" => email}

    case create_user_and_log_in(user_attrs, author_attrs) do
      {:ok, user} ->
        log_in_and_redirect(user, conn, ~p"/welcome")

      {:error, _, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp create_or_log_in_user(user, email, author_attrs, conn) do
    user_attrs = %{"email" => email}

    with {:ok, user} <- Accounts.update_login_with_x(user, user_attrs),
         {:ok, _} <- Authors.update_author(user.author, author_attrs) do
      log_in_and_redirect(user, conn)
    else
      {:error, changeset} -> show_error(changeset, conn)
    end
  end

  defp create_user_and_log_in(user_attrs, author_attrs) do
    user_attrs = Map.put(user_attrs, :twin_enabled, false)

    case Accounts.register_user(user_attrs, author_attrs) do
      {:ok, %{user: user, author: _author}} ->
        Track.event("New user", user)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp log_in_and_redirect(user, conn, path \\ ~p"/") do
    conn
    |> YouCongressWeb.UserAuth.log_in_user_without_redirect(user)
    |> put_flash(:info, "Welcome!")
    |> redirect(to: path)
  end

  defp show_error(changeset, conn) do
    Logger.error("Error creating user: #{inspect(changeset)}")

    conn
    |> put_flash(:error, "There was an error.")
    |> redirect(to: "/")
  end
end
