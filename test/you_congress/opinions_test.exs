defmodule YouCongress.OpinionsTest do
  use YouCongress.DataCase

  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions
  alias YouCongress.Votes

  describe "add_opinion_to_statement/3" do
    test "returns already_associated when the link exists" do
      opinion = opinion_fixture()
      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement, opinion.user_id)

      assert {:error, :already_associated} =
               Opinions.add_opinion_to_statement(opinion, statement, user_fixture().id)

      %{statements: statements} = Opinions.get_opinion!(opinion.id, preload: [:statements])
      assert length(statements) == 1
    end
  end

  describe "delete_opinion/1" do
    test "deletes inferred author votes for quote opinions" do
      quote = opinion_fixture(%{twin: false})
      statement_1 = statement_fixture()
      statement_2 = statement_fixture()
      other_statement = statement_fixture()
      other_author_vote = vote_fixture(%{statement_id: statement_1.id})

      assert {:ok, _} = Opinions.add_opinion_to_statement(quote, statement_1)
      assert {:ok, _} = Opinions.add_opinion_to_statement(quote, statement_2)

      inferred_vote_1 =
        vote_fixture(%{
          statement_id: statement_1.id,
          author_id: quote.author_id,
          answer: :for
        })

      inferred_vote_2 =
        vote_fixture(%{
          statement_id: statement_2.id,
          author_id: quote.author_id,
          answer: :against
        })

      unrelated_vote =
        vote_fixture(%{
          statement_id: other_statement.id,
          author_id: quote.author_id,
          answer: :abstain
        })

      assert {:ok, _deleted_quote} = Opinions.delete_opinion(quote)

      assert Votes.get_vote(inferred_vote_1.id) == nil
      assert Votes.get_vote(inferred_vote_2.id) == nil
      assert Votes.get_vote(unrelated_vote.id) != nil
      assert Votes.get_vote(other_author_vote.id) != nil
    end

    test "keeps author votes for non-quote opinions" do
      opinion = opinion_fixture(%{source_url: nil, twin: false})
      statement = statement_fixture()

      assert {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: opinion.author_id,
          answer: :for
        })

      assert {:ok, _deleted_opinion} = Opinions.delete_opinion(opinion)

      assert Votes.get_vote(vote.id) != nil
    end
  end
end
