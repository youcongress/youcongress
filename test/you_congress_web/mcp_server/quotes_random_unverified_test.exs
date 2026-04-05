defmodule YouCongressWeb.MCPServer.QuotesRandomUnverifiedTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions
  alias YouCongressWeb.MCPServer.QuotesRandomUnverified

  describe "execute/2" do
    test "returns a random unverified quote with statements and votes" do
      statement = statement_fixture(%{title: "Tax carbon emissions"})
      opinion = opinion_fixture(%{content: "We need to tax carbon to save the planet."})
      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: opinion.author_id,
          opinion_id: opinion.id,
          answer: :for
        })

      with_mocked_response(fn ->
        assert {:reply, {:json, %{quote: quote_payload, statements: [statement_payload]}}, :frame} =
                 QuotesRandomUnverified.execute(%{}, :frame)

        assert quote_payload.opinion_id == opinion.id
        assert quote_payload.quote == "We need to tax carbon to save the planet."
        assert statement_payload.statement_id == statement.id
        assert statement_payload.statement_title == statement.title
        assert statement_payload.vote.vote_id == vote.id
        assert statement_payload.vote.answer == :for
      end)
    end

    test "skips quotes from unsupported sources" do
      statement = statement_fixture(%{title: "End partisan gerrymandering"})

      excluded_tweet =
        opinion_fixture(%{
          content: "This thread is wild",
          source_url: "https://twitter.com/someone/status/1"
        })

      allowed_article =
        opinion_fixture(%{
          content: "We must end partisan gerrymandering immediately.",
          source_url: "https://example.com/opinion"
        })

      {:ok, _} = Opinions.add_opinion_to_statement(excluded_tweet, statement)
      {:ok, _} = Opinions.add_opinion_to_statement(allowed_article, statement)

      with_mocked_response(fn ->
        assert {:reply, {:json, %{quote: quote_payload}}, :frame} =
                 QuotesRandomUnverified.execute(%{}, :frame)

        assert quote_payload.opinion_id == allowed_article.id
        assert quote_payload.source_url == "https://example.com/opinion"
      end)
    end

    test "returns deterministic error when no unverified quotes exist" do
      with_mocked_response(fn ->
        assert {:reply, {:error, "No unverified quotes available."}, :frame} =
                 QuotesRandomUnverified.execute(%{}, :frame)
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
       ]},
      {Anubis.Server.Frame, [],
       [
         get_query_param: fn _frame, _key -> nil end
       ]}
    ]) do
      fun.()
    end
  end
end
