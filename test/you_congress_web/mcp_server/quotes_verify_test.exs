defmodule YouCongressWeb.MCPServer.QuotesVerifyTest do
  use YouCongress.DataCase, async: false
  use Oban.Testing, repo: YouCongress.Repo

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongressWeb.MCPServer.QuotesVerify
  alias YouCongress.Workers.VerificationWorker

  defp disable_automatic_verifications do
    original = Application.fetch_env(:you_congress, :feature_flags)

    flags =
      case original do
        {:ok, map} when is_map(map) -> Map.put(map, :automatic_verifications, false)
        _ -> %{automatic_verifications: false}
      end

    Application.put_env(:you_congress, :feature_flags, flags)

    on_exit(fn ->
      case original do
        {:ok, original_value} ->
          Application.put_env(:you_congress, :feature_flags, original_value)

        :error ->
          Application.delete_env(:you_congress, :feature_flags)
      end
    end)
  end

  describe "execute/2" do
    test "enqueues relation verification when marking a quote ai_verified" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      {opinion, opinion_statement} = quote_link_fixture(admin)

      Oban.Testing.with_testing_mode(:manual, fn ->
        with_mocked_response_and_key(api_key.token, fn frame ->
          assert {:reply, {:json, %{verification: payload}}, ^frame} =
                   QuotesVerify.execute(
                     %{
                       opinion_id: opinion.id,
                       status: "ai_verified",
                       comment: "Authentic quote",
                       model: "claude-opus-4.6"
                     },
                     frame
                   )

          assert payload.opinion_id == opinion.id
          assert payload.status == "ai_verified"
        end)

        assert_enqueued(
          worker: VerificationWorker,
          args: %{"subject" => "relevance", "id" => opinion_statement.id}
        )
      end)
    end

    test "does not enqueue relation verification when automatic verifications are disabled" do
      disable_automatic_verifications()

      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      {opinion, opinion_statement} = quote_link_fixture(admin)

      Oban.Testing.with_testing_mode(:manual, fn ->
        with_mocked_response_and_key(api_key.token, fn frame ->
          assert {:reply, {:json, %{verification: payload}}, ^frame} =
                   QuotesVerify.execute(
                     %{
                       opinion_id: opinion.id,
                       status: "ai_verified",
                       comment: "Authentic quote",
                       model: "claude-opus-4.6"
                     },
                     frame
                   )

          assert payload.opinion_id == opinion.id
          assert payload.status == "ai_verified"
        end)

        refute_enqueued(
          worker: VerificationWorker,
          args: %{"subject" => "relevance", "id" => opinion_statement.id}
        )
      end)
    end

    test "does not enqueue relation verification for non-ai-verified quote statuses" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      {opinion, opinion_statement} = quote_link_fixture(admin)

      Oban.Testing.with_testing_mode(:manual, fn ->
        with_mocked_response_and_key(api_key.token, fn frame ->
          assert {:reply, {:json, %{verification: payload}}, ^frame} =
                   QuotesVerify.execute(
                     %{
                       opinion_id: opinion.id,
                       status: "ai_unverifiable",
                       comment: "Could not confirm the quote",
                       model: "claude-opus-4.6"
                     },
                     frame
                   )

          assert payload.status == "ai_unverifiable"
        end)

        refute_enqueued(
          worker: VerificationWorker,
          args: %{"subject" => "relevance", "id" => opinion_statement.id}
        )
      end)
    end
  end

  defp quote_link_fixture(user) do
    opinion = opinion_fixture(%{author_id: user.author_id, user_id: user.id})
    statement = statement_fixture()

    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)
    opinion_statement = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

    {opinion, opinion_statement}
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
       ]}
    ]) do
      frame = Anubis.Server.Frame.new(%{query_params: %{"key" => key}})
      fun.(frame)
    end
  end
end
