defmodule YouCongress.MCP.ToolUsageTrackerTest do
  use YouCongress.DataCase, async: true

  import Mock
  import YouCongress.AccountsFixtures

  alias Anubis.Server.Frame
  alias YouCongress.Accounts
  alias YouCongress.MCP.ToolUsageTracker

  describe "track/3" do
    test "returns the user lookup result and includes user_id in the event" do
      user = user_fixture()

      {:ok, api_key} =
        Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :write})

      frame = build_frame(%{"key" => api_key.token})

      with_mock YouCongress.Amplitude,
        track_event: fn event_type, user_id, props ->
          send(self(), {:event, event_type, user_id, props})
          :ok
        end do
        assert {:ok, ^user} =
                 ToolUsageTracker.track(YouCongressWeb.MCPServer.StatementsSearch, frame)

        user_id = user.id
        assert_received {:event, "MCP Tool Used", ^user_id, props}
        assert props["tool_name"] == "statements_search"
        assert props["session_id"] == "session-123"
        assert props["client_name"] == "Test Client"
        assert props["client_version"] == "1.0"
        assert props["used_api_key"]
        assert props["api_key_present"]
      end
    end

    test "reports null user_id when API key is missing" do
      frame = build_frame(%{})

      with_mock YouCongress.Amplitude,
        track_event: fn event_type, user_id, props ->
          send(self(), {:event, event_type, user_id, props})
          :ok
        end do
        assert {:error, :missing_api_key} =
                 ToolUsageTracker.track(YouCongressWeb.MCPServer.StatementsSearch, frame)

        assert_received {:event, "MCP Tool Used", nil, props}
        refute props["used_api_key"]
        refute props["api_key_present"]
      end
    end
  end

  defp build_frame(query_params) do
    %Frame{
      assigns: %{query_params: query_params},
      context: %Anubis.Server.Context{
        session_id: "session-123",
        client_info: %{"name" => "Test Client", "version" => "1.0"}
      }
    }
  end
end
