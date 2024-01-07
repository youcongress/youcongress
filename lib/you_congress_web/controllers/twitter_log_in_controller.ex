defmodule YouCongressWeb.TwitterLogInController do
  use YouCongressWeb, :controller

  require Logger

  def log_in(conn, _params) do
    token = ExTwitter.request_token("http://localhost:4000/twitter-callback")

    case ExTwitter.authenticate_url(token.oauth_token) do
      {:ok, authenticate_url} ->
        redirect(conn, external: authenticate_url)

      error ->
        Logger.error("Error authenticating with Twitter: #{inspect(error)}")

        conn
        |> put_flash(:error, "There was an error with Twitter. Please try again later.")
        |> redirect(to: "/")
    end
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

    Logger.info("screen_name: #{data.screen_name}")
    Logger.info("raw_data.email: #{data.raw_data.email}")
    Logger.info("name: #{data.name}")
    Logger.info("profile_image_url_https: #{data.profile_image_url_https}")
    Logger.info("description: #{data.description}")
    Logger.info("location: #{data.location}")
    Logger.info("followers_count: #{data.followers_count}")
    Logger.info("verified: #{data.verified}")

    data
    |> Map.from_struct()
    |> Enum.each(fn {key, value} -> Logger.info("#{key}: #{inspect(value)}") end)

    text(conn, "ok")
  end
end
