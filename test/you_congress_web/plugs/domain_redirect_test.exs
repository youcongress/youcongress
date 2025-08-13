defmodule YouCongressWeb.Plugs.DomainRedirectTest do
  use YouCongressWeb.ConnCase
  alias YouCongressWeb.Plugs.DomainRedirect

  defp conn_with_host_and_path(conn, host, path, query_string \\ "") do
    conn = %{
      conn
      | req_headers: [{"host", host} | conn.req_headers],
        request_path: path,
        query_string: query_string
    }

    # Set scheme to https for tests
    %{conn | scheme: :https}
  end

  describe "domain redirect" do
    test "redirects www.youcongress.org to youcongress.org", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("www.youcongress.org", "/")

      conn = DomainRedirect.call(conn, [])

      assert conn.status == 301
      assert conn.halted == true
      assert get_resp_header(conn, "location") == ["https://youcongress.org/"]
    end

    test "redirects youcongress.com to youcongress.org", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("youcongress.com", "/some/path", "param=value")

      conn = DomainRedirect.call(conn, [])

      assert conn.status == 301
      assert conn.halted == true

      assert get_resp_header(conn, "location") == [
               "https://youcongress.org/some/path?param=value"
             ]
    end

    test "redirects www.youcongress.com to youcongress.org", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("www.youcongress.com", "/polls")

      conn = DomainRedirect.call(conn, [])

      assert conn.status == 301
      assert conn.halted == true
      assert get_resp_header(conn, "location") == ["https://youcongress.org/polls"]
    end

    test "does not redirect youcongress.org", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("youcongress.org", "/")

      conn = DomainRedirect.call(conn, [])

      # Connection should be unchanged (not halted)
      assert conn.halted == false
      assert conn.status == nil
    end

    test "does not redirect other domains", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("example.com", "/")

      conn = DomainRedirect.call(conn, [])

      # Connection should be unchanged (not halted)
      assert conn.halted == false
      assert conn.status == nil
    end

    test "preserves query parameters in redirect", %{conn: conn} do
      conn =
        conn
        |> conn_with_host_and_path("www.youcongress.org", "/search", "q=test&page=2")

      conn = DomainRedirect.call(conn, [])

      assert conn.status == 301
      assert conn.halted == true
      assert get_resp_header(conn, "location") == ["https://youcongress.org/search?q=test&page=2"]
    end
  end
end
