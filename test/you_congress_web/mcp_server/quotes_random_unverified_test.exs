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
       ]}
    ]) do
      fun.()
    end
  end
end
