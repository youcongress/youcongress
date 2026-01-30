defmodule YouCongressWeb.Plugs.MCPSessionPlugTest do
  use YouCongressWeb.ConnCase, async: true

  import Plug.Conn

  alias YouCongressWeb.Plugs.MCPSessionPlug

  @cookie "_you_congress_mcp_session"

  test "hydrates the header from the cookie" do
    conn =
      build_conn()
      |> put_req_header("cookie", "#{@cookie}=session-123")
      |> MCPSessionPlug.call([])

    assert get_req_header(conn, "mcp-session-id") == ["session-123"]
  end

  test "stores the cookie and exposes the header" do
    conn =
      build_conn()
      |> MCPSessionPlug.call([])
      |> put_resp_header("mcp-session-id", "session-456")
      |> send_resp(200, "ok")

    assert conn.resp_cookies[@cookie].value == "session-456"
    assert get_resp_header(conn, "access-control-expose-headers") |> hd() =~ "mcp-session-id"
  end
end
