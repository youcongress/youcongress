defmodule YouCongressWeb.TwitterLogInController do
  use YouCongressWeb, :controller

  require Logger

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Accounts.User
  alias YouCongress.Track

  def log_in(conn, _params) do
    base_url = Application.get_env(:you_congress, :base_url)
    token = ExTwitter.request_token(base_url <> "/twitter-callback")

    {:ok, authenticate_url} = ExTwitter.authenticate_url(token.oauth_token)
    redirect(conn, external: authenticate_url)
  end

  def callback(conn, %{"oauth_token" => oauth_token, "oauth_verifier" => oauth_verifier}) do
    data = YouCongressWeb.TwitterLogInController.get_callback_data(oauth_token, oauth_verifier)

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
      friends_count: data.friends_count,
      verified: data.verified
    }

    email = data.raw_data.email

    invitation = YouCongress.Invitations.get_invitation_by_twitter_username(data.screen_name)
    user = Accounts.get_user_by_twitter_id_str_or_username(data.id_str, data.screen_name)
    create_or_log_in_user(invitation, user, email, author_attrs, conn)
  end

  def get_callback_data(oauth_token, oauth_verifier) do
    {:ok, access_token} = ExTwitter.access_token(oauth_verifier, oauth_token)

    ExTwitter.configure(
      consumer_key: System.get_env("TWITTER_CONSUMER_KEY"),
      consumer_secret: System.get_env("TWITTER_CONSUMER_SECRET"),
      access_token: access_token.oauth_token,
      access_token_secret: access_token.oauth_token_secret
    )

    ExTwitter.verify_credentials(include_email: true)
  end

  defp create_or_log_in_user(nil, nil, email, author_attrs, conn) do
    user_attrs = %{"role" => "waiting_list", "email" => email}

    case Accounts.register_user(user_attrs, author_attrs) do
      {:ok, %{user: user, author: _author}} ->
        user = YouCongress.Accounts.get_user!(user.id, include: [:author])
        Track.event("Join Waiting List", user)

        conn
        |> put_flash(:error, "You're in the waiting list. See you soon.")
        |> redirect(to: ~p"/waiting_list")

      {:error, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp create_or_log_in_user(nil, user, email, author_attrs, conn) do
    user_attrs = %{"email" => email}

    with {:ok, user} <- Accounts.update_login_with_x(user, user_attrs),
         {:ok, _} <- Authors.update_author(user.author, author_attrs) do
      if Accounts.in_waiting_list?(user) do
        Track.event("Rejoin Waiting List", user)
        redirect(conn, to: ~p"/waiting_list")
      else
        log_in_and_redirect(user, conn)
      end
    else
      {:error, changeset} -> show_error(changeset, conn)
    end
  end

  defp create_or_log_in_user(invitation, nil, email, author_attrs, conn) do
    user_attrs = %{"role" => "user", "email" => email}

    case create_user_and_log_in(user_attrs, author_attrs) do
      {:ok, user} ->
        YouCongress.Invitations.delete_invitation(invitation)
        log_in_and_redirect(user, conn, ~p"/welcome")

      {:error, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp create_or_log_in_user(invitation, user, _data, _author_attrs, conn) do
    case maybe_change_role(user) do
      :ok ->
        YouCongress.Invitations.delete_invitation(invitation)
        log_in_and_redirect(user, conn, ~p"/welcome")

      {:error, changeset} ->
        show_error(changeset, conn)
    end
  end

  defp maybe_change_role(%User{role: "waiting_list"} = user) do
    case Accounts.update_role(user, "user") do
      {:ok, user} ->
        Track.event("New user", user)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp maybe_change_role(user) do
    Track.event("Login with X", user)
    :ok
  end

  defp create_user_and_log_in(user_attrs, author_attrs) do
    case Accounts.register_user(user_attrs, author_attrs) do
      {:ok, %{user: user, author: _author}} ->
        Track.event("New user", user)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp log_in_and_redirect(user, conn, path \\ ~p"/home") do
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
