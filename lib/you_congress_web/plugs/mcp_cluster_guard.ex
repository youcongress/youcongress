defmodule YouCongressWeb.Plugs.MCPClusterGuard do
  @moduledoc """
  Ensures that MCP requests are routed to the Fly.io instance that holds the session.
  """
  import Plug.Conn
  require Logger

  @registry Anubis.Server.Registry
  @server YouCongressWeb.MCPServer

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case get_session_id(conn) do
      nil ->
        conn

      session_id ->
        if session_exists_locally?(session_id) do
          conn
        else
          attempt_replay(conn, session_id)
        end
    end
  end

  defp get_session_id(conn) do
    header_session =
      conn
      |> get_req_header("mcp-session-id")
      |> List.first()

    cond do
      is_binary(header_session) and header_session != "" -> header_session
      true -> conn.cookies["_you_congress_mcp_session"]
    end
  end

  defp session_exists_locally?(session_id) do
    case Registry.lookup(@registry, {:session, @server, session_id}) do
      [{_pid, _value}] -> true
      _ -> false
    end
  end

  defp attempt_replay(conn, session_id) do
    # Find which node has the session
    case YouCongressWeb.ClusterUtils.find_session_owner(__MODULE__, :check_instance_for_session, [
           session_id
         ]) do
      {:ok, instance_id} ->
        Logger.info("Replaying MCP request for session #{session_id} to instance #{instance_id}")

        conn
        |> put_resp_header("fly-replay", "instance=#{instance_id}")
        # Fly.io intercepts this, body doesn't matter much but usually empty
        |> send_resp(200, "")
        |> halt()

      nil ->
        log_missing_session(session_id)
        conn
    end
  end

  @doc false
  def check_instance_for_session(session_id) do
    if session_exists_locally?(session_id) do
      {:ok, System.get_env("FLY_ALLOC_ID")}
    else
      :error
    end
  end

  defp log_missing_session(session_id) do
    level = if Application.get_env(:you_congress, :env) == :prod, do: :warning, else: :debug
    Logger.log(level, "MCP session #{session_id} not found on any node. Passing through.")
  end
end
