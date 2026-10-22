defmodule YouCongressWeb.Plugs.ContentSecurityPolicyTest do
  use YouCongressWeb.ConnCase

  alias YouCongressWeb.Plugs.ContentSecurityPolicy

  defmodule ProductionEndpoint do
    def url, do: "https://youcongress.org"
  end

  test "browser responses enforce CSP with unique nonces and retain secure headers", %{conn: conn} do
    first = get(conn, "/about")
    second = get(build_conn(), "/about")
    [policy] = get_resp_header(first, "content-security-policy")
    nonce = first.assigns.csp_nonce

    assert byte_size(Base.decode64!(nonce)) == 16
    refute nonce == second.assigns.csp_nonce
    assert policy =~ "'nonce-#{nonce}'"
    assert get_resp_header(first, "content-security-policy-report-only") == []
    assert get_resp_header(first, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(first, "x-frame-options") == ["SAMEORIGIN"]
    assert get_resp_header(first, "referrer-policy") == ["strict-origin-when-cross-origin"]

    directives = directives(policy)
    assert directives["default-src"] == ["'self'"]
    assert directives["object-src"] == ["'none'"]
    assert directives["base-uri"] == ["'self'"]
    assert directives["form-action"] == ["'self'"]
    assert directives["frame-ancestors"] == ["'self'"]
    refute "'unsafe-inline'" in directives["script-src"]
    refute "'unsafe-eval'" in directives["script-src"]
    refute "*" in directives["script-src"]

    for origin <- [
          "https://plausible.io",
          "https://challenges.cloudflare.com",
          "https://cdn.jsdelivr.net",
          "https://tally.so"
        ] do
      assert origin in directives["script-src"]
    end

    for origin <- [
          "https://challenges.cloudflare.com",
          "https://tally.so",
          "https://www.youtube-nocookie.com"
        ] do
      assert origin in directives["frame-src"]
    end
  end

  test "WebSocket sources use endpoint configuration, never request headers" do
    conn =
      Plug.Test.conn(:get, "http://attacker.example/about")
      |> put_req_header("x-forwarded-host", "attacker.example")
      |> put_private(:phoenix_endpoint, ProductionEndpoint)
      |> ContentSecurityPolicy.call([])

    [policy] = get_resp_header(conn, "content-security-policy")
    assert "wss://youcongress.org" in directives(policy)["connect-src"]
    refute policy =~ "attacker.example"
    refute policy =~ "ws://"
  end

  test "local HTTP endpoint supports local WebSockets", %{conn: conn} do
    conn = ContentSecurityPolicy.call(conn, [])
    [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "ws://localhost"
  end

  test "Oban inline scripts carry the authorized nonce", %{conn: conn} do
    start_supervised!({Oban.Met, conf: Oban.config()})

    start_supervised!(
      {Oban.Sonar,
       conf: %{Oban.config() | testing: :disabled}, name: Oban.Registry.via(Oban, Oban.Sonar)}
    )

    conn = conn |> log_in_as_admin() |> get("/oban")
    html = html_response(conn, 200)
    document = Floki.parse_document!(html)
    nonce = conn.assigns.csp_nonce
    scripts = Floki.find(document, "script:not([src])")

    assert scripts != []
    assert Enum.all?(scripts, &(Floki.attribute(&1, "nonce") == [nonce]))
    assert hd(get_resp_header(conn, "content-security-policy")) =~ "'nonce-#{nonce}'"
  end

  defp directives(policy) do
    Map.new(String.split(policy, "; "), fn directive ->
      [name | sources] = String.split(directive)
      {name, sources}
    end)
  end
end
