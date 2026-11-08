defmodule YouCongressWeb.MCPServer.TrustNetworkTest do
  use YouCongress.DataCase
  import Mock
  import YouCongress.AccountsFixtures
  alias YouCongress.Accounts
  alias YouCongressWeb.MCPServer.TrustNetwork

  test "ranking reads require an admin key while ordinary public lists remain readable" do
    admin = admin_fixture()
    member = user_fixture()

    {:ok, admin_key} =
      Accounts.create_api_key_for_user(admin, %{"name" => "Trust preview", "scope" => :read})

    {:ok, member_key} =
      Accounts.create_api_key_for_user(member, %{"name" => "Member", "scope" => :read})

    frames =
      for key <- [nil, member_key.token],
          do: %Anubis.Server.Frame{assigns: %{query_params: %{"key" => key}}}

    admin_frame = %Anubis.Server.Frame{assigns: %{query_params: %{"key" => admin_key.token}}}

    with_mock Anubis.Server.Response, tool: fn -> :tool end, json: fn :tool, data -> data end do
      for frame <- frames do
        assert {:reply, %{error: "Trust List rankings are currently available to admins only."},
                _} = TrustNetwork.execute(%{view: "rankings"}, frame)

        assert {:reply, [], _} =
                 TrustNetwork.execute(%{view: "lists", author_id: member.author_id}, frame)
      end

      assert {:reply, %{rows: [], participants: 0}, _} =
               TrustNetwork.execute(%{view: "rankings"}, admin_frame)
    end
  end
end
