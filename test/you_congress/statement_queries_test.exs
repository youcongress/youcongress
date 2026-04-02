defmodule YouCongress.Statements.StatementQueriesTest do
  use YouCongress.DataCase

  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions
  alias YouCongress.Statements.StatementQueries
  alias YouCongress.Votes

  describe "get_opinion_cards_by_recency/1" do
    test "returns each quote only once even if multiple votes point to it" do
      statement = statement_fixture()
      opinion_author = author_fixture()

      opinion =
        opinion_fixture(%{
          author_id: opinion_author.id,
          twin: false
        })

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement.id)

      first_vote_author = author_fixture()

      {:ok, _} =
        Votes.create_vote(%{
          author_id: first_vote_author.id,
          statement_id: statement.id,
          opinion_id: opinion.id,
          answer: :for
        })

      second_vote_author = author_fixture()

      {:ok, _} =
        Votes.create_vote(%{
          author_id: second_vote_author.id,
          statement_id: statement.id,
          opinion_id: opinion.id,
          answer: :for
        })

      fill_statement_with_quotes(statement.id)

      cards = StatementQueries.get_opinion_cards_by_recency(limit: 20)

      # The statement should appear exactly once despite multiple votes
      matching_cards =
        Enum.filter(cards, fn card ->
          card.statement.id == statement.id
        end)

      assert length(matching_cards) == 1
    end
  end
end
