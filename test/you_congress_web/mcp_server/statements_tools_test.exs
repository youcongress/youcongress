defmodule YouCongressWeb.MCPServer.StatementsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.HallsStatements
  alias YouCongress.OpinionsStatements
  alias YouCongressWeb.MCPServer.StatementsHallsUpdate
  alias YouCongressWeb.MCPServer.StatementsList
  alias YouCongressWeb.MCPServer.StatementsShow

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

  describe "StatementsShow.execute/2" do
    test "returns title, halls, and authors" do
      statement = statement_fixture(title: "AI Charter")
      {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "ai", other_tags: ["climate"]})

      author = author_fixture(name: "Ada Lovelace")
      opinion = opinion_fixture(author_id: author.id)

      {:ok, _opinion_statement} =
        OpinionsStatements.create_opinion_statement(%{
          opinion_id: opinion.id,
          statement_id: statement.id,
          user_id: opinion.user_id
        })

      with_mocked_response(fn ->
        assert {:reply, {:json, %{statement: payload}}, :frame} =
                 StatementsShow.execute(%{statement_id: statement.id}, :frame)

        assert payload.statement_id == statement.id
        assert payload.title == "AI Charter"
        assert Enum.map(payload.halls, & &1.name) == ["ai", "climate"]
        assert Enum.map(payload.authors, & &1.name) == ["Ada Lovelace"]
      end)
    end

    test "returns error when statement does not exist" do
      with_mocked_response(fn ->
        assert {:reply, {:error, "Statement not found."}, :frame} =
                 StatementsShow.execute(%{statement_id: -1}, :frame)
      end)
    end
  end

  describe "StatementsHallsUpdate.execute/2" do
    test "updates halls when admin provides API key" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      statement = statement_fixture(title: "Energy plan")

      params = %{
        statement_id: statement.id,
        main_hall: "ai",
        other_halls: "climate, future"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{statement: payload}}, :frame} =
                 StatementsHallsUpdate.execute(params, :frame)

        assert payload.statement_id == statement.id
        assert payload.main_hall == "ai"
        assert Enum.map(payload.halls, & &1.name) == ["ai", "climate", "future"]
      end)
    end

    test "parses delimited strings for other hall tags" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      statement = statement_fixture(title: "Workforce")

      params = %{
        statement_id: statement.id,
        main_hall: "ai",
        halls: "climate; future-of-work\nfuture-of-work"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{statement: payload}}, :frame} =
                 StatementsHallsUpdate.execute(params, :frame)

        assert Enum.map(payload.halls, & &1.name) == ["ai", "climate", "future-of-work"]
      end)
    end

    test "requires API key" do
      statement = statement_fixture(title: "Tax policy")

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, message}, :frame} =
                 StatementsHallsUpdate.execute(%{statement_id: statement.id, main_hall: "ai"}, :frame)

        assert message == "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
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

  defp with_mocked_response_and_key(key, fun) do
    with_mocks([
      {Anubis.Server.Response, [],
       [
         tool: fn -> :tool end,
         json: fn :tool, data -> {:json, data} end,
         error: fn :tool, message -> {:error, message} end
       ]},
      {Anubis.Server.Frame, [],
       [
         get_query_param: fn _frame, "key" -> key end
       ]}
    ]) do
      fun.()
    end
  end

  defp api_key_fixture(user) do
    {:ok, api_key} = Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :write})
    api_key
  end
end
