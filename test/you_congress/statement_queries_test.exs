defmodule YouCongress.Statements.StatementQueriesTest do
  use YouCongress.DataCase

  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

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

      cards = StatementQueries.get_opinion_cards_by_recency(limit: 10)

      matching_cards =
        Enum.filter(cards, fn card ->
          card.statement.id == statement.id && card.vote.opinion.id == opinion.id
        end)

      assert length(matching_cards) == 1
    end
  end
end
