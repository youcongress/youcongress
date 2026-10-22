defmodule YouCongressWeb.Plugs.ProductionSSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  defmodule ProductionEndpoint do
    def host, do: "youcongress.org"
  end

  setup do
    config = Config.Reader.read!("config/prod.exs", env: :prod)
    endpoint = config[:you_congress][YouCongressWeb.Endpoint]
    ssl = Phoenix.Endpoint.__force_ssl__(ProductionEndpoint, endpoint) |> Plug.SSL.init()
    %{ssl: ssl}
  end

  test "HTTP redirects to the configured host and preserves path/query", %{ssl: ssl} do
    conn = conn(:get, "http://untrusted.example/p/policy?source=users&answer=for")
    conn = Plug.SSL.call(conn, ssl)

    assert conn.status == 301
    assert conn.halted

    assert get_resp_header(conn, "location") ==
             ["https://youcongress.org/p/policy?source=users&answer=for"]
  end

  test "HTTP POST redirects preserve the request method", %{ssl: ssl} do
    conn = conn(:post, "http://youcongress.org/users/live_login") |> Plug.SSL.call(ssl)
    assert conn.status == 307
  end

  test "Fly forwarded HTTPS avoids loops and enables HSTS and secure cookies", %{ssl: ssl} do
    conn =
      conn(:get, "http://youcongress.org/settings")
      |> put_req_header("x-forwarded-proto", "https")
      |> Plug.SSL.call(ssl)

    assert conn.scheme == :https
    refute conn.halted
    assert get_resp_header(conn, "location") == []
    [hsts] = get_resp_header(conn, "strict-transport-security")
    assert hsts =~ "max-age="
    refute hsts =~ "includeSubDomains"
    refute hsts =~ "preload"

    conn = conn |> put_resp_cookie("session_test", "value") |> send_resp(200, "OK")
    assert Enum.any?(get_resp_header(conn, "set-cookie"), &String.contains?(&1, "; secure"))
  end

  test "local development remains HTTP" do
    config = Config.Reader.read!("config/config.exs", env: :dev)
    refute config[:you_congress][YouCongressWeb.Endpoint][:force_ssl]
  end
end
