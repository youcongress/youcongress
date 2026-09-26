defmodule YouCongressWeb.MCPServer.AuthenticationTransportTest do
  use YouCongressWeb.ConnCase, async: false

  import Plug.Conn
  import YouCongress.AccountsFixtures

  alias YouCongress.Accounts

  setup do
    start_supervised!(
      {YouCongressWeb.MCPServer,
       transport: {:streamable_http, start: true}, session_idle_timeout: :timer.minutes(1)}
    )

    :ok
  end

  test "authenticates tool calls with the key in the MCP URL" do
    admin = admin_fixture()

    {:ok, api_key} =
      Accounts.create_api_key_for_user(admin, %{"name" => "MCP transport", "scope" => :write})

    endpoint = "/mcp?key=#{api_key.token}"

    initialize = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-03-26",
        "clientInfo" => %{"name" => "Authentication transport test", "version" => "1.0"},
        "capabilities" => %{}
      }
    }

    conn = mcp_post(build_conn(), endpoint, initialize)

    assert conn.status == 200
    assert [session_id] = get_resp_header(conn, "mcp-session-id")

    initialized = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/initialized"
    }

    assert build_conn()
           |> put_req_header("mcp-session-id", session_id)
           |> mcp_post(endpoint, initialized)
           |> Map.fetch!(:status) == 202

    call = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "authors_update",
        "arguments" => %{"author_id" => -1, "name" => "Missing author"}
      }
    }

    response =
      build_conn()
      |> put_req_header("mcp-session-id", session_id)
      |> mcp_post(endpoint, call)

    assert response.status == 200

    body = Jason.decode!(response.resp_body)
    assert get_in(body, ["result", "isError"])
    assert [%{"text" => "Author not found."}] = get_in(body, ["result", "content"])
  end

  defp mcp_post(conn, endpoint, message) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> post(endpoint, Jason.encode!(message))
  end
end
