defmodule YouCongressWeb.MCPServer.VotesToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Accounts
  alias YouCongress.Votes
  alias YouCongressWeb.MCPServer.VotesEdit

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @not_found_message "Vote not found."

  describe "VotesEdit.execute/2" do
    test "updates a vote when authenticated and authorized" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)
      vote = vote_fixture(%{author_id: owner.author_id, answer: :for})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{vote: payload}}, :frame} =
                 VotesEdit.execute(
                   %{
                     statement_id: vote.statement_id,
                     author_id: vote.author_id,
                     answer: "against"
                   },
                   :frame
                 )

        assert payload.vote_id == vote.id
        assert payload.statement_id == vote.statement_id
        assert payload.author_id == vote.author_id
        assert payload.answer == "against"
      end)

      assert Votes.get_by(%{statement_id: vote.statement_id, author_id: vote.author_id}).answer ==
               :against
    end

    test "returns an error when no updatable fields are provided" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)
      vote = vote_fixture(%{author_id: owner.author_id})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Provide at least one field to update: answer."}, :frame} =
                 VotesEdit.execute(
                   %{statement_id: vote.statement_id, author_id: vote.author_id},
                   :frame
                 )
      end)
    end

    test "returns missing-key error when no API key is provided" do
      vote = vote_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 VotesEdit.execute(
                   %{
                     statement_id: vote.statement_id,
                     author_id: vote.author_id,
                     answer: "against"
                   },
                   :frame
                 )
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      vote = vote_fixture()

      with_mocked_response_and_key("invalid-token", fn ->
        assert {:reply, {:error, @invalid_key_message}, :frame} =
                 VotesEdit.execute(
                   %{
                     statement_id: vote.statement_id,
                     author_id: vote.author_id,
                     answer: "against"
                   },
                   :frame
                 )
      end)
    end

    test "returns forbidden when caller cannot edit the target vote" do
      owner = user_fixture()
      other_user = user_fixture()
      api_key = api_key_fixture(other_user)
      vote = vote_fixture(%{author_id: owner.author_id, answer: :for})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Your account is not allowed to edit this vote."}, :frame} =
                 VotesEdit.execute(
                   %{
                     statement_id: vote.statement_id,
                     author_id: vote.author_id,
                     answer: "against"
                   },
                   :frame
                 )
      end)

      assert Votes.get_by(%{statement_id: vote.statement_id, author_id: vote.author_id}).answer ==
               :for
    end

    test "returns deterministic not-found error for a missing vote" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 VotesEdit.execute(%{statement_id: -1, author_id: -1, answer: "against"}, :frame)
      end)
    end
  end

  defp api_key_fixture(user) do
    {:ok, api_key} = Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :write})
    api_key
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
