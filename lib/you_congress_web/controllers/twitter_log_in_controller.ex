defmodule YouCongressWeb.TwitterLogInController do
  use YouCongressWeb, :controller

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Authors

  def log_in(conn, _params) do
    base_url = "#{conn.scheme}://#{conn.host}:#{conn.port}"
    token = ExTwitter.request_token(base_url <> "/twitter-callback")

    {:ok, authenticate_url} = ExTwitter.authenticate_url(token.oauth_token)
    redirect(conn, external: authenticate_url)
  end

  def callback(conn, %{"oauth_token" => oauth_token, "oauth_verifier" => oauth_verifier}) do
    {:ok, access_token} = ExTwitter.access_token(oauth_verifier, oauth_token)

    ExTwitter.configure(
      consumer_key: System.get_env("TWITTER_CONSUMER_KEY"),
      consumer_secret: System.get_env("TWITTER_CONSUMER_SECRET"),
      access_token: access_token.oauth_token,
      access_token_secret: access_token.oauth_token_secret
    )

    data = ExTwitter.verify_credentials(include_email: true)

    # Inspect the data returned by Twitter:
    #
    # data
    # |> Map.from_struct()
    # |> Enum.each(fn {key, value} -> Logger.info("#{key}: #{inspect(value)}") end)

    author_attrs = %{
      twitter_username: data.screen_name,
      twitter_id_str: data.id_str,
      name: data.name,
      profile_image_url: data.profile_image_url_https,
      description: data.description,
      location: data.location,
      followers_count: data.followers_count,
      verified: data.verified
    }

    invitation = YouCongress.Invitations.get_invitation_by_twitter_username(data.screen_name)

    if invitation do
      case Accounts.get_user_by_twitter_id_str_or_username(data.id_str, data.screen_name) do
        nil ->
          user_attrs = %{"role" => "user", "email" => data.raw_data.email}
          create_user_and_log_in(user_attrs, author_attrs, conn, invitation)

        user ->
          case Accounts.update_role(user, "user") do
            {:ok, user} -> log_in_and_redirect_to_home(user, conn)
            {:error, changeset} -> show_error(changeset, conn)
          end
      end
    else
      case Accounts.get_user_by_twitter_id_str_or_username(data.id_str, data.screen_name) do
        nil ->
          user_attrs = %{"role" => "waiting_list", "email" => data.raw_data.email}
          create_user_and_redirect_to_waiting_list(user_attrs, author_attrs, conn)

        user ->
          user_attrs = %{"email" => data.raw_data.email}
          log_in_or_redirect_to_waiting_list(user, user_attrs, author_attrs, conn)
      end
    end
  end

  defp create_user_and_log_in(user_attrs, author_attrs, conn, invitation) do
    case Accounts.register_user(user_attrs, author_attrs) do
      {:ok, %{user: user, author: _author}} ->
        YouCongress.Invitations.delete_invitation(invitation)
        log_in_and_redirect_to_home(user, conn)

      {:error, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp create_user_and_redirect_to_waiting_list(user_attrs, author_attrs, conn) do
    case Accounts.register_user(user_attrs, author_attrs) do
      {:ok, %{user: _user, author: _author}} ->
        conn
        |> put_flash(:error, "You're in the waiting list. See you soon.")
        |> redirect(to: ~p"/waiting_list")

      {:error, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp log_in_or_redirect_to_waiting_list(user, user_attrs, author_attrs, conn) do
    with {:ok, user} <- Accounts.update_login_with_x(user, user_attrs),
         {:ok, _} <- Authors.update_author(user.author, author_attrs) do
      if Accounts.in_waiting_list?(user) do
        redirect(conn, to: ~p"/waiting_list")
      else
        log_in_and_redirect_to_home(user, conn)
      end
    else
      {:error, changeset} -> show_error(changeset, conn)
    end
  end

  defp log_in_and_redirect_to_home(user, conn) do
    conn
    |> YouCongressWeb.UserAuth.log_in_user(user)
    |> put_flash(:info, "Welcome!")
    |> redirect(to: "/home")
  end

  defp show_error(changeset, conn) do
    Logger.error("Error creating user: #{inspect(changeset)}")

    conn
    |> put_flash(:error, "There was an error.")
    |> redirect(to: "/")
  end
end
