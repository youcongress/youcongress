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
    # Ensure query params are fetched
    conn = fetch_query_params(conn)

    case conn.query_params["sessionId"] do
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
        # If no one has it, pass through and let it fail normally (or start new if that's the logic)
        Logger.warning("MCP session #{session_id} not found on any node. Passing through.")
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
end
