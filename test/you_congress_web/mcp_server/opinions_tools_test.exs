defmodule YouCongressWeb.MCPServer.OpinionsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Accounts
  alias YouCongress.Opinions
  alias YouCongress.Votes
  alias YouCongressWeb.MCPServer.OpinionsCreate
  alias YouCongressWeb.MCPServer.OpinionsDelete
  alias YouCongressWeb.MCPServer.OpinionsEdit
  alias YouCongressWeb.MCPServer.OpinionsShow
  alias YouCongressWeb.MCPServer.OpinionsStatementsAdd
  alias YouCongressWeb.MCPServer.OpinionsStatementsRemove

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @not_found_message "Opinion not found."
  @invalid_vote_answer_message "Answer must be one of: For, Abstain, Against."

  describe "OpinionsShow.execute/2" do
    test "returns a serialized opinion payload" do
      opinion = opinion_fixture(%{content: "Universal healthcare is essential."})
      statement = statement_fixture(%{title: "Universal healthcare should be a right."})
      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      vote =
        vote_fixture(%{
          author_id: opinion.author_id,
          statement_id: statement.id,
          answer: :against
        })

      with_mocked_response(fn ->
        assert {:reply, {:json, %{opinion: payload}}, :frame} =
                 OpinionsShow.execute(%{opinion_id: opinion.id}, :frame)

        assert payload.opinion_id == opinion.id
        assert payload.content == "Universal healthcare is essential."
        assert payload.author_id == opinion.author_id

        assert [statement_payload] = payload.statements
        assert statement_payload.statement_id == statement.id
        assert statement_payload.statement_title == "Universal healthcare should be a right."
        assert statement_payload.vote_id == vote.id
        assert statement_payload.vote_answer == :against
      end)
    end

    test "returns a deterministic not-found error" do
      with_mocked_response(fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 OpinionsShow.execute(%{opinion_id: -1}, :frame)
      end)
    end
  end

  describe "OpinionsCreate.execute/2" do
    test "creates an opinion when authenticated and authorized" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      opinion_id =
        with_mocked_response_and_key(api_key.token, fn ->
          assert {:reply, {:json, %{opinion: payload}}, :frame} =
                   OpinionsCreate.execute(
                     %{
                       content: "We should invest more in quantum research.",
                       author_id: owner.author_id,
                       source_url: "https://example.com",
                       year: 2026
                     },
                     :frame
                   )

          assert payload.content == "We should invest more in quantum research."
          assert payload.author_id == owner.author_id
          assert payload.source_url == "https://example.com"
          assert payload.year == 2026

          opinion = Opinions.get_opinion!(payload.opinion_id)
          assert opinion.user_id == owner.id

          payload.opinion_id
        end)

      opinion = Opinions.get_opinion!(opinion_id)
      assert opinion.content == "We should invest more in quantum research."
      assert opinion.author_id == owner.author_id
      assert opinion.user_id == owner.id
    end

    test "returns missing-key error when no API key is provided" do
      owner = user_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 OpinionsCreate.execute(
                   %{content: "Education is vital.", author_id: owner.author_id},
                   :frame
                 )
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      owner = user_fixture()

      with_mocked_response_and_key("invalid-token", fn ->
        assert {:reply, {:error, @invalid_key_message}, :frame} =
                 OpinionsCreate.execute(
                   %{content: "Democracy must be protected.", author_id: owner.author_id},
                   :frame
                 )
      end)
    end

    test "returns forbidden when caller cannot create for the author" do
      owner = user_fixture()
      other_user = user_fixture()
      api_key = api_key_fixture(other_user)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Your account is not allowed to create this opinion."}, :frame} =
                 OpinionsCreate.execute(
                   %{content: "Universal childcare now.", author_id: owner.author_id},
                   :frame
                 )
      end)
    end

    test "returns validation errors when creation fails" do
      owner = user_fixture()
      api_key = api_key_fixture(owner)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Could not create opinion: source_url is not a valid URL"},
                :frame} =
                 OpinionsCreate.execute(
                   %{
                     content: "Healthcare should be universal.",
                     author_id: owner.author_id,
                     source_url: "ftp://example.com"
                   },
                   :frame
                 )
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

  describe "OpinionsStatementsAdd.execute/2" do
    test "attaches an opinion to a statement when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, payload}, :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "For"},
                   :frame
                 )

        assert payload.attached
        assert payload.opinion_id == opinion.id
        assert payload.statement_id == statement.id
        assert payload.statement_title == statement.title
        assert payload.vote.answer == "for"
        assert payload.vote.author_id == opinion.author_id
      end)

      opinion = Opinions.get_opinion!(opinion.id, preload: [:statements])
      assert Enum.any?(opinion.statements, &(&1.id == statement.id))

      vote = Votes.get_by(%{statement_id: statement.id, author_id: opinion.author_id})
      assert vote
      assert vote.answer == :for
      assert vote.opinion_id == opinion.id
    end

    test "returns missing-key error when no API key is provided" do
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "For"},
                   :frame
                 )
      end)
    end

    test "returns forbidden when caller lacks permission" do
      user = user_fixture()
      api_key = api_key_fixture(user)
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Your account is not allowed to attach opinions to statements."},
                :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "Against"},
                   :frame
                 )
      end)
    end

    test "returns an error when the opinion is already attached" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      opinion = opinion_fixture()
      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Opinion is already associated with this statement."}, :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "Abstain"},
                   :frame
                 )
      end)
    end

    test "returns an error when answer is outside the allowed values" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @invalid_vote_answer_message}, :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "maybe"},
                   :frame
                 )
      end)

      refute Votes.get_by(%{statement_id: statement.id, author_id: opinion.author_id})
    end

    test "updates an existing vote when the author already voted for the statement" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      statement = statement_fixture()
      existing_vote = vote_fixture(%{statement_id: statement.id, answer: :against})
      opinion = opinion_fixture(%{author_id: existing_vote.author_id})

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, payload}, :frame} =
                 OpinionsStatementsAdd.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id, vote_answer: "For"},
                   :frame
                 )

        assert payload.vote.vote_id == existing_vote.id
        assert payload.vote.answer == "for"
      end)

      vote = Votes.get_by(%{statement_id: statement.id, author_id: opinion.author_id})
      assert vote.id == existing_vote.id
      assert vote.answer == :for
      assert vote.opinion_id == opinion.id
    end
  end

  describe "OpinionsStatementsRemove.execute/2" do
    test "removes an opinion from a statement when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      opinion = opinion_fixture()
      statement = statement_fixture()
      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, payload}, :frame} =
                 OpinionsStatementsRemove.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id},
                   :frame
                 )

        assert payload.removed
        assert payload.opinion_id == opinion.id
        assert payload.statement_id == statement.id
      end)

      opinion = Opinions.get_opinion!(opinion.id, preload: [:statements])
      refute Enum.any?(opinion.statements, &(&1.id == statement.id))
    end

    test "returns missing-key error when no API key is provided" do
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 OpinionsStatementsRemove.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id},
                   :frame
                 )
      end)
    end

    test "returns forbidden when caller lacks permission" do
      user = user_fixture()
      api_key = api_key_fixture(user)
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply,
                {:error, "Your account is not allowed to remove opinions from statements."},
                :frame} =
                 OpinionsStatementsRemove.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id},
                   :frame
                 )
      end)
    end

    test "returns an error when the opinion is not attached" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      opinion = opinion_fixture()
      statement = statement_fixture()

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, "Opinion is not associated with this statement."}, :frame} =
                 OpinionsStatementsRemove.execute(
                   %{opinion_id: opinion.id, statement_id: statement.id},
                   :frame
                 )
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
       ]},
      {Anubis.Server.Frame, [],
       [
         get_query_param: fn _frame, _key -> nil end
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
