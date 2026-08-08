defmodule YouCongressWeb.Plugs.AiBasicAuthTest do
  use YouCongressWeb.ConnCase

  setup do
    previous = Application.get_env(:you_congress, :ai_basic_auth)
    previous_flags = Application.get_env(:you_congress, :feature_flags)
    flags = Map.new(previous_flags || %{}) |> Map.put(:ai_policy_launch, false)
    Application.put_env(:you_congress, :feature_flags, flags)

    on_exit(fn ->
      Application.put_env(:you_congress, :ai_basic_auth, previous)
      Application.put_env(:you_congress, :feature_flags, previous_flags)
    end)

    :ok
  end

  describe "with credentials configured" do
    setup do
      Application.put_env(:you_congress, :ai_basic_auth, username: "ai", password: "secret")
      :ok
    end

    test "asks for credentials on /ai", %{conn: conn} do
      conn = get(conn, ~p"/ai")

      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") != []
    end

    test "asks for credentials on /ai-welcome", %{conn: conn} do
      conn = get(conn, ~p"/ai-welcome")

      assert conn.status == 401
    end

    test "rejects wrong credentials", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("ai", "wrong"))
        |> get(~p"/ai")

      assert conn.status == 401
    end

    test "lets the right credentials through", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("ai", "secret"))
        |> get(~p"/ai")

      assert html_response(conn, 200) =~ "100 AI Policies"
    end

    test "launch flag bypasses preview credentials", %{conn: conn} do
      flags = Application.get_env(:you_congress, :feature_flags, %{})
      Application.put_env(:you_congress, :feature_flags, Map.put(flags, :ai_policy_launch, true))

      conn = get(conn, ~p"/ai")

      assert html_response(conn, 200) =~ "Help find 100 AI policies"
      refute conn.resp_body =~ "Private preview"
    end
  end

  test "stays open when no credentials are configured", %{conn: conn} do
    Application.put_env(:you_congress, :ai_basic_auth, username: nil, password: nil)

    assert html_response(get(conn, ~p"/ai"), 200)
  end
end
