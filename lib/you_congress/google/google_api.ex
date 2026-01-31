defmodule YouCongress.Google.GoogleAPI do
  @moduledoc """
  Google OAuth 2.0 API client for authentication.
  """

  require Logger

  @doc """
  Generates the Google OAuth 2.0 authorization URL.
  Returns {url, state} where state is used for CSRF protection.
  """
  def generate_authorize_url(client_id, callback_url) do
    state = generate_state()

    query_params = %{
      client_id: client_id,
      response_type: "code",
      scope: "openid email profile",
      state: state,
      redirect_uri: callback_url,
      access_type: "offline",
      prompt: "select_account"
    }

    url = "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_query(query_params)}"
    {url, state}
  end

  @doc """
  Exchanges the authorization code for access token.
  """
  def fetch_token(code, callback_url) do
    client_id = Application.get_env(:you_congress, :google_client_id)
    client_secret = Application.get_env(:you_congress, :google_client_secret)

    body =
      URI.encode_query(%{
        "code" => code,
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "client_secret" => client_secret,
        "redirect_uri" => callback_url
      })

    case Req.post(
           "https://oauth2.googleapis.com/token",
           body: body,
           headers: [
             {"Content-Type", "application/x-www-form-urlencoded"}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body["access_token"]}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Google token exchange failed: status=#{status}, body=#{inspect(body)}")

        {:error,
         "Token exchange failed: #{body["error_description"] || body["error"] || "Unknown error"}"}

      {:error, reason} ->
        Logger.error("Google token exchange request failed: #{inspect(reason)}")
        {:error, "Request failed"}
    end
  end

  @doc """
  Fetches user information from Google API using the access token.
  Returns user data including id, email, name, and picture.
  """
  def fetch_user_info(access_token) do
    url = "https://www.googleapis.com/oauth2/v2/userinfo"

    case Req.get(
           url,
           headers: [
             {"Authorization", "Bearer #{access_token}"}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: user_data}} ->
        {:ok, normalize_user_data(user_data)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Google user info fetch failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to fetch user info"}

      {:error, reason} ->
        Logger.error("Google user info request failed: #{inspect(reason)}")
        {:error, "Request failed"}
    end
  end

  defp normalize_user_data(data) do
    %{
      google_id: data["id"],
      email: data["email"],
      name: data["name"],
      profile_image_url: data["picture"],
      email_verified: data["verified_email"] || false
    }
  end

  # Generate a random state parameter for CSRF protection
  defp generate_state do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
