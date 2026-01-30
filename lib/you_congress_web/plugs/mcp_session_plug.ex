defmodule YouCongressWeb.Plugs.MCPSessionPlug do
  @moduledoc """
  Keeps the MCP session identifier stable across HTTP requests.

  Browser-based MCP clients cannot always read custom response headers, so the
  plug mirrors the `mcp-session-id` header into a cookie and rehydrates it on
  subsequent requests. This ensures that transports like Claude's MCP UI send
  the session ID consistently, which lets the cluster guard route requests to
  the correct Fly instance.
  """

  import Plug.Conn

  @behaviour Plug

  @header "mcp-session-id"
  @cookie "_you_congress_mcp_session"
  @default_cookie_opts [
    http_only: false,
    secure: true,
    same_site: "None",
    path: "/mcp",
    max_age: 1_800
  ]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> fetch_cookies()
    |> maybe_apply_session_from_cookie()
    |> register_before_send(&persist_session_cookie/1)
  end

  defp maybe_apply_session_from_cookie(conn) do
    case get_req_header(conn, @header) do
      [] ->
        case conn.cookies[@cookie] do
          nil -> conn
          session -> put_req_header(conn, @header, session)
        end

      _ ->
        conn
    end
  end

  defp persist_session_cookie(conn) do
    conn
    |> maybe_store_cookie()
    |> ensure_header_exposed()
  end

  defp maybe_store_cookie(conn) do
    case get_resp_header(conn, @header) do
      [session_id | _] when is_binary(session_id) and session_id != "" ->
        put_resp_cookie(conn, @cookie, session_id, cookie_opts())

      _ ->
        conn
    end
  end

  defp ensure_header_exposed(conn) do
    case get_resp_header(conn, "access-control-expose-headers") do
      [] ->
        put_resp_header(conn, "access-control-expose-headers", @header)

      [value | _] ->
        headers =
          value
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        if Enum.any?(headers, &(String.downcase(&1) == @header)) do
          conn
        else
          updated =
            headers
            |> Enum.concat([@header])
            |> Enum.join(", ")

          put_resp_header(conn, "access-control-expose-headers", updated)
        end
    end
  end

  defp cookie_opts do
    Application.get_env(:you_congress, :mcp_session_cookie_opts, @default_cookie_opts)
  end
end
