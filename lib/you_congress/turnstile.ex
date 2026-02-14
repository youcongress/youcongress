defmodule YouCongress.Turnstile do
  @moduledoc """
  Verifies Cloudflare Turnstile tokens to protect forms from bots.
  """

  require Logger

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc """
  Verifies a Turnstile response token with Cloudflare's API.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  When `turnstile_enabled` config is `false` (e.g. in tests), always returns `{:ok, %{}}`.
  """
  def verify(token) do
    if enabled?() do
      do_verify(token)
    else
      {:ok, %{}}
    end
  end

  defp enabled? do
    Application.get_env(:you_congress, :turnstile_enabled, true)
  end

  defp do_verify(nil), do: {:error, "missing-input-response"}
  defp do_verify(""), do: {:error, "missing-input-response"}

  defp do_verify(token) do
    secret_key = Application.get_env(:you_congress, :turnstile_secret_key)

    body =
      URI.encode_query(%{
        "secret" => secret_key,
        "response" => token
      })

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    case Req.post(@verify_url, body: body, headers: headers) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true} = resp}} ->
        {:ok, resp}

      {:ok, %Req.Response{status: 200, body: %{"success" => false} = resp}} ->
        Logger.warning("Turnstile verification failed: #{inspect(resp)}")
        {:error, "verification failed"}

      {:error, reason} ->
        Logger.error("Turnstile API request failed: #{inspect(reason)}")
        {:error, "api request failed"}
    end
  end
end
