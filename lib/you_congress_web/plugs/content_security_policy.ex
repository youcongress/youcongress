defmodule YouCongressWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Enforces the browser resource policy and supplies a nonce to dashboard layouts.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.encode64()
    endpoint = conn.private[:phoenix_endpoint] || YouCongressWeb.Endpoint

    policy =
      [
        "default-src 'self'",
        "base-uri 'self'",
        "object-src 'none'",
        "frame-ancestors 'self'",
        "form-action 'self'",
        "script-src 'self' 'nonce-#{nonce}' https://plausible.io https://challenges.cloudflare.com https://cdn.jsdelivr.net https://tally.so",
        "style-src 'self' 'unsafe-inline'",
        "img-src 'self' data: https:",
        "font-src 'self' data:",
        "connect-src 'self' #{websocket_origin(endpoint.url())} https://plausible.io",
        "frame-src 'self' https://challenges.cloudflare.com https://tally.so https://www.youtube-nocookie.com"
      ]
      |> Enum.join("; ")

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy)
  end

  defp websocket_origin(endpoint_url) do
    uri = URI.parse(endpoint_url)
    scheme = if uri.scheme == "https", do: "wss", else: "ws"
    URI.to_string(%{uri | scheme: scheme, path: nil, query: nil, fragment: nil})
  end
end
