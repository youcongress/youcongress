defmodule YouCongressWeb.Plugs.MCPClusterGuardTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  import Mock

  alias YouCongressWeb.Plugs.MCPClusterGuard

  test "passes through when no session id is present" do
    conn = conn(:get, "/mcp")
    conn = MCPClusterGuard.call(conn, [])
    refute conn.halted
  end

  test "passes through when session exists locally" do
    with_mock Registry, lookup: fn _registry, _key -> [{self(), nil}] end do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("mcp-session-id", "local-session")
        |> MCPClusterGuard.call([])

      refute conn.halted
    end
  end

  test "replays when session exists remotely" do
    with_mocks([
      {Registry, [], [lookup: fn _registry, _key -> [] end]},
      {YouCongressWeb.ClusterUtils, [],
       [find_session_owner: fn _mod, _func, _args -> {:ok, "instance-123"} end]}
    ]) do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("mcp-session-id", "remote-session")
        |> MCPClusterGuard.call([])

      assert conn.halted
      assert {"fly-replay", "instance=instance-123"} in conn.resp_headers
    end
  end

  test "passes through when session not found anywhere" do
    with_mocks([
      {Registry, [], [lookup: fn _registry, _key -> [] end]},
      {YouCongressWeb.ClusterUtils, [], [find_session_owner: fn _mod, _func, _args -> nil end]}
    ]) do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("mcp-session-id", "unknown-session")
        |> MCPClusterGuard.call([])

      refute conn.halted
    end
  end

  test "uses cookie when header missing" do
    with_mocks([
      {Registry, [], [lookup: fn _registry, _key -> [] end]},
      {YouCongressWeb.ClusterUtils, [],
       [find_session_owner: fn _mod, _func, _args -> {:ok, "instance-456"} end]}
    ]) do
      conn =
        conn(:get, "/mcp")
        |> put_req_header("cookie", "_you_congress_mcp_session=cookie-session")
        |> MCPClusterGuard.call([])

      assert conn.halted
      assert {"fly-replay", "instance=instance-456"} in conn.resp_headers
    end
  end
end
