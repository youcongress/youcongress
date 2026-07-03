defmodule YouCongressWeb.MCPServer.QuotesSearchTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Opinions
  alias YouCongress.Repo
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongressWeb.MCPServer.QuotesSearch

  describe "execute/2" do
    test "returns each quote's cached verification status" do
      statement = statement_fixture(%{title: "Price carbon emissions"})

      human_quote = quote_fixture(statement, "Carbon quote reviewed by a person.")
      ai_quote = quote_fixture(statement, "Carbon quote reviewed by AI.")
      ai_disputed_quote = quote_fixture(statement, "Carbon quote disputed by AI.")
      unverified_quote = quote_fixture(statement, "Carbon quote waiting for review.")

      reviewer = user_fixture()

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: human_quote.id,
          user_id: reviewer.id,
          status: :verified,
          comment: "Human verified"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: ai_quote.id,
          user_id: reviewer.id,
          status: :ai_verified,
          comment: "AI verified",
          model: "opus-4.6"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: ai_disputed_quote.id,
          user_id: reviewer.id,
          status: :disputed,
          comment: "AI disputed",
          model: "opus-4.6"
        })

      assert Opinions.get_opinion!(ai_quote.id).verification_status == :ai_verified
      assert Opinions.get_opinion!(ai_disputed_quote.id).verification_status == :disputed

      with_mocked_response(fn ->
        assert {:reply, {:json, %{matches: matches, more_quotes: []}}, :frame} =
                 QuotesSearch.execute(%{statement_id: statement.id, query: "carbon"}, :frame)

        payload_by_id = Map.new(matches, fn payload -> {payload.opinion_id, payload} end)

        assert Map.keys(payload_by_id) |> Enum.sort() ==
                 [human_quote.id, ai_quote.id, ai_disputed_quote.id, unverified_quote.id]
                 |> Enum.sort()

        assert payload_by_id[human_quote.id].verification_status == :verified
        assert payload_by_id[ai_quote.id].verification_status == :ai_verified
        assert payload_by_id[ai_disputed_quote.id].verification_status == :disputed
        assert payload_by_id[unverified_quote.id].verification_status == :unverified
      end)
    end

    test "without statement_id and with a valid API key, runs semantic similarity search" do
      statement = statement_fixture(%{title: "Price carbon emissions"})

      quote =
        statement
        |> quote_fixture("Carbon pricing is the most effective policy.")
        |> Repo.preload(:author)

      similar_quote = %{quote | similarity: 0.91}

      api_key = api_key_fixture(user_fixture())
      frame = Anubis.Server.Frame.new(%{query_params: %{"key" => api_key.token}})

      with_mocks([
        {Anubis.Server.Response, [],
         [
           tool: fn -> :tool end,
           json: fn :tool, data -> {:json, data} end,
           error: fn :tool, message -> {:error, message} end
         ]},
        {Opinions, [:passthrough], [get_by_content_similarity: fn _query -> [similar_quote] end]}
      ]) do
        assert {:reply, {:json, %{matches: matches, more_quotes: []}}, ^frame} =
                 QuotesSearch.execute(%{query: "carbon tax"}, frame)

        assert [%{opinion_id: opinion_id, similarity: 0.91}] = matches
        assert opinion_id == quote.id
      end
    end

    test "without statement_id and without an API key, is rejected without embedding" do
      with_mocks([
        {Anubis.Server.Response, [],
         [
           tool: fn -> :tool end,
           json: fn :tool, data -> {:json, data} end,
           error: fn :tool, message -> {:error, message} end
         ]},
        {Opinions, [:passthrough],
         [
           get_by_content_similarity: fn _query ->
             flunk("semantic search must not generate an embedding without an API key")
           end
         ]}
      ]) do
        assert {:reply, {:error, message}, :frame} =
                 QuotesSearch.execute(%{query: "carbon tax"}, :frame)

        assert message =~ "API key"
      end
    end
  end

  defp api_key_fixture(user) do
    {:ok, api_key} = Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :read})
    api_key
  end

  defp quote_fixture(statement, content) do
    opinion =
      opinion_fixture(%{
        content: content,
        source_url: "https://example.com/#{System.unique_integer([:positive])}"
      })

    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

    {:ok, _} =
      Votes.create_vote(%{
        statement_id: statement.id,
        author_id: opinion.author_id,
        opinion_id: opinion.id,
        answer: :for
      })

    opinion
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
