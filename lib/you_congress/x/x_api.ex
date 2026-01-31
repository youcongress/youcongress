defmodule YouCongress.X.XAPI do
  @moduledoc """
  X (Twitter) API V2 for OAuth authentication.
  """

  require Logger

  @doc """
  Generates the X OAuth 2.0 authorization URL with PKCE.
  """
  def generate_authorize_url(client_id, callback_url) do
    # Generate a random code verifier for PKCE
    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)
    state = generate_state()

    query_params = %{
      client_id: client_id,
      response_type: "code",
      scope: "users.read tweet.read",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      state: state,
      redirect_uri: callback_url
    }

    url = "https://twitter.com/i/oauth2/authorize?#{URI.encode_query(query_params)}"
    {url, code_verifier, state}
  end

  @doc """
  Exchanges the authorization code for access and refresh tokens.
  """
  def fetch_token(code, code_verifier, callback_url) do
    client_id = Application.get_env(:you_congress, :x_client_id)

    body =
      URI.encode_query(%{
        "code" => code,
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "redirect_uri" => callback_url,
        "code_verifier" => code_verifier
      })

    case Req.post(
           "https://api.twitter.com/2/oauth2/token",
           body: body,
           headers: [
             {"Content-Type", "application/x-www-form-urlencoded"},
             {"Authorization", generate_auth_header()}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body["access_token"], body["refresh_token"]}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X token exchange failed: status=#{status}, body=#{inspect(body)}")

        {:error,
         "Token exchange failed: #{body["error_description"] || body["error"] || "Unknown error"}"}

      {:error, reason} ->
        Logger.error("X token exchange request failed: #{inspect(reason)}")
        {:error, "Request failed"}
    end
  end

  @doc """
  Fetches user information from X API using the access token.
  Returns user data including id, username, name, and profile_image_url.
  """
  def fetch_user_info(access_token) do
    url =
      "https://api.twitter.com/2/users/me?user.fields=id,username,name,profile_image_url,description,public_metrics,verified"

    case Req.get(
           url,
           headers: [
             {"Authorization", "Bearer #{access_token}"}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: %{"data" => user_data}}} ->
        {:ok, normalize_user_data(user_data)}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X user info fetch failed: status=#{status}, body=#{inspect(body)}")
        {:error, "Failed to fetch user info"}

      {:error, reason} ->
        Logger.error("X user info request failed: #{inspect(reason)}")
        {:error, "Request failed"}
    end
  end

  defp normalize_user_data(data) do
    %{
      twitter_id_str: data["id"],
      twitter_username: data["username"],
      name: data["name"],
      email: data["email"],
      profile_image_url: normalize_profile_image_url(data["profile_image_url"]),
      description: data["description"],
      followers_count: get_in(data, ["public_metrics", "followers_count"]),
      friends_count: get_in(data, ["public_metrics", "following_count"]),
      verified: data["verified"] || false
    }
  end

  # X returns small profile images by default (_normal). Replace with larger version.
  defp normalize_profile_image_url(nil), do: nil

  defp normalize_profile_image_url(url) do
    String.replace(url, "_normal", "_400x400")
  end

  defp generate_auth_header do
    client_id = Application.get_env(:you_congress, :x_client_id)
    secret = Application.get_env(:you_congress, :x_client_secret)

    "Basic " <> Base.encode64(client_id <> ":" <> secret)
  end

  # Generate a cryptographically random code verifier (43-128 characters)
  defp generate_code_verifier do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  # Generate code challenge from verifier using SHA256
  defp generate_code_challenge(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  # Generate a random state parameter for CSRF protection
  defp generate_state do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end
end
