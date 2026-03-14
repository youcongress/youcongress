defmodule YouCongressWeb.MCPServer.OpinionsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Accounts
  alias YouCongress.Opinions
  alias YouCongressWeb.MCPServer.OpinionsDelete
  alias YouCongressWeb.MCPServer.OpinionsEdit
  alias YouCongressWeb.MCPServer.OpinionsShow

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @not_found_message "Opinion not found."

  describe "OpinionsShow.execute/2" do
    test "returns a serialized opinion payload" do
      opinion = opinion_fixture(%{content: "Universal healthcare is essential."})

      with_mocked_response(fn ->
        assert {:reply, {:json, %{opinion: payload}}, :frame} =
                 OpinionsShow.execute(%{opinion_id: opinion.id}, :frame)

        assert payload.opinion_id == opinion.id
        assert payload.content == "Universal healthcare is essential."
        assert payload.author_id == opinion.author_id
        assert payload.statements == []
      end)
    end

    test "includes associated statements with vote details" do
      opinion = opinion_fixture(%{content: "AI labs should be liable for model misuse."})

      statement =
        statement_fixture(%{title: "Impose liability for frontier model deployments"})

      other_statement =
        statement_fixture(%{title: "Require public incident reporting for large AI systems"})

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, other_statement)
      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: opinion.author_id,
          opinion_id: opinion.id,
          answer: :for
        })

      other_vote =
        vote_fixture(%{
          statement_id: other_statement.id,
          author_id: opinion.author_id,
          opinion_id: opinion.id,
          answer: :against
        })

      with_mocked_response(fn ->
        assert {:reply, {:json, %{opinion: payload}}, :frame} =
                 OpinionsShow.execute(%{opinion_id: opinion.id}, :frame)

        assert payload.statements == [
                 %{
                   statement_id: statement.id,
                   title: statement.title,
                   vote_id: vote.id,
                   answer: "for"
                 },
                 %{
                   statement_id: other_statement.id,
                   title: other_statement.title,
                   vote_id: other_vote.id,
                   answer: "against"
                 }
               ]
      end)
    end

    test "returns a deterministic not-found error" do
      with_mocked_response(fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 OpinionsShow.execute(%{opinion_id: -1}, :frame)
      end)
    end
  end

  describe "OpinionsEdit.execute/2" do
    test "updates an opinion when authenticated and authorized" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      opinion =
        opinion_fixture(%{user_id: owner.id, author_id: owner.author_id, content: "Before"})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{opinion: payload}}, :frame} =
                 OpinionsEdit.execute(%{opinion_id: opinion.id, content: "After"}, :frame)

        assert payload.content == "After"
      end)

      assert Opinions.get_opinion!(opinion.id).content == "After"
    end

    test "returns an error when no updatable fields are provided" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)
      opinion = opinion_fixture(%{user_id: owner.id, author_id: owner.author_id})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply,
                {:error,
                 "Provide at least one field to update: content, source_url, year, author_id."},
                :frame} =
                 OpinionsEdit.execute(%{opinion_id: opinion.id}, :frame)
      end)
    end

    test "returns missing-key error when no API key is provided" do
      opinion = opinion_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 OpinionsEdit.execute(%{opinion_id: opinion.id, content: "After"}, :frame)
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      opinion = opinion_fixture()

      with_mocked_response_and_key("invalid-token", fn ->
        assert {:reply, {:error, @invalid_key_message}, :frame} =
                 OpinionsEdit.execute(%{opinion_id: opinion.id, content: "After"}, :frame)
      end)
    end

    test "returns forbidden when caller cannot edit target opinion" do
      owner = user_fixture()
      other_user = user_fixture()
      api_key = api_key_fixture(other_user)

      opinion =
        opinion_fixture(%{user_id: owner.id, author_id: owner.author_id, content: "Before"})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Your account is not allowed to edit this opinion."}, :frame} =
                 OpinionsEdit.execute(%{opinion_id: opinion.id, content: "After"}, :frame)
      end)

      assert Opinions.get_opinion!(opinion.id).content == "Before"
    end

    test "returns deterministic not-found error for missing opinion" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 OpinionsEdit.execute(%{opinion_id: -1, content: "After"}, :frame)
      end)
    end
  end

  describe "OpinionsDelete.execute/2" do
    test "deletes an opinion when authenticated and authorized" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)
      opinion = opinion_fixture(%{user_id: owner.id, author_id: owner.author_id})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{deleted: true, deleted_opinion_id: deleted_id}}, :frame} =
                 OpinionsDelete.execute(%{opinion_id: opinion.id}, :frame)

        assert deleted_id == opinion.id
      end)

      assert Opinions.get_opinion(opinion.id) == nil
    end

    test "returns missing-key error when no API key is provided" do
      opinion = opinion_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 OpinionsDelete.execute(%{opinion_id: opinion.id}, :frame)
      end)
    end

    test "returns forbidden when caller cannot delete target opinion" do
      owner = user_fixture()
      other_user = user_fixture()
      api_key = api_key_fixture(other_user)
      opinion = opinion_fixture(%{user_id: owner.id, author_id: owner.author_id})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Your account is not allowed to delete this opinion."}, :frame} =
                 OpinionsDelete.execute(%{opinion_id: opinion.id}, :frame)
      end)

      assert Opinions.get_opinion(opinion.id)
    end

    test "returns deterministic not-found error for missing opinion" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 OpinionsDelete.execute(%{opinion_id: -1}, :frame)
      end)
    end
  end

  defp api_key_fixture(user) do
    {:ok, api_key} = Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :write})
    api_key
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
end
