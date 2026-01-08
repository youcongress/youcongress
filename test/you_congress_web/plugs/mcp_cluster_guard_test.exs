defmodule YouCongressWeb.Plugs.MCPClusterGuardTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Mock

  alias YouCongressWeb.Plugs.MCPClusterGuard

  test "passes through when no sessionId is present" do
    conn = conn(:get, "/mcp")
    conn = MCPClusterGuard.call(conn, [])
    refute conn.halted
  end

  test "passes through when session exists locally" do
    # Mock Registry.lookup to return a pid (simulating local session)
    with_mock Registry, lookup: fn _registry, _key -> [{self(), nil}] end do
      conn = conn(:get, "/mcp?sessionId=local-session")
      conn = MCPClusterGuard.call(conn, [])
      refute conn.halted
    end
  end

  test "replays when session exists remotely" do
    # Mock Registry.lookup to return nothing locally
    # Mock ClusterUtils to find it remotely
    with_mocks([
      {Registry, [], [lookup: fn _registry, _key -> [] end]},
      {YouCongressWeb.ClusterUtils, [],
       [find_session_owner: fn _mod, _func, _args -> {:ok, "instance-123"} end]}
    ]) do
      conn = conn(:get, "/mcp?sessionId=remote-session")
      conn = MCPClusterGuard.call(conn, [])

      assert conn.halted
      assert {"fly-replay", "instance=instance-123"} in conn.resp_headers
    end
  end

  test "passes through when session not found anywhere" do
    with_mocks([
      {Registry, [], [lookup: fn _registry, _key -> [] end]},
      {YouCongressWeb.ClusterUtils, [], [find_session_owner: fn _mod, _func, _args -> nil end]}
    ]) do
      conn = conn(:get, "/mcp?sessionId=unknown-session")
      conn = MCPClusterGuard.call(conn, [])

      refute conn.halted
    end
  end
end
