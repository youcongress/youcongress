defmodule YouCongressWeb.MCPServer.StatementsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.StatementsFixtures

  alias YouCongress.HallsStatements
  alias YouCongressWeb.MCPServer.StatementsList

  describe "StatementsList.execute/2" do
    test "returns statements without halls by default" do
      statement = statement_fixture(title: "AI Charter")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{statements: payload}}, :frame} =
                 StatementsList.execute(%{}, :frame)

        assert result = Enum.find(payload, &(&1.id == statement.id))
        assert result.title == "AI Charter"
        refute Map.has_key?(result, :halls)
      end)
    end

    test "includes hall data when requested" do
      statement = statement_fixture(title: "Climate plan")
      {:ok, _statement} =
        HallsStatements.sync!(statement.id, %{main_tag: "ai", other_tags: ["climate"]})

      with_mocked_response(fn ->
        assert {:reply, {:json, %{statements: payload}}, :frame} =
                 StatementsList.execute(%{include_halls: true}, :frame)

        assert %{halls: halls} = Enum.find(payload, &(&1.id == statement.id))
        assert Enum.map(halls, & &1.name) == ["ai", "climate"]
        assert Enum.all?(halls, fn hall -> is_integer(hall.id) end)
      end)
    end
  end

  defp with_mocked_response(fun) do
    with_mocks([
      {Anubis.Server.Response, [],
       [
         tool: fn -> :tool end,
         json: fn :tool, data -> {:json, data} end,
         error: fn :tool, message -> {:error, message} end
       ]}
    ]) do
      fun.()
    end
  end
end
