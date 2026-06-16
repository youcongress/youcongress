defmodule YouCongress.Statements.StatementQueriesTest do
  use YouCongress.DataCase

  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.Statements.StatementQueries
  alias YouCongress.Votes

  defp verify_relevance(opinion, statement) do
    opinion.id
    |> OpinionsStatements.get_opinion_statement(statement.id)
    |> Ecto.Changeset.change(verification_status: :ai_verified)
    |> YouCongress.Repo.update!()
  end

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

    test "uses the newest positive verified opinion before newer disputed opinions" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 8)

      verified_author = author_fixture()

      verified_opinion =
        opinion_fixture(%{
          author_id: verified_author.id,
          content: "Older verified home quote",
          verification_status: :ai_verified
        })

      {:ok, _} = Opinions.add_opinion_to_statement(verified_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: verified_author.id,
        opinion_id: verified_opinion.id
      })

      disputed_author = author_fixture()

      disputed_opinion =
        opinion_fixture(%{
          author_id: disputed_author.id,
          content: "Newer disputed home quote",
          verification_status: :disputed
        })

      {:ok, _} = Opinions.add_opinion_to_statement(disputed_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: disputed_author.id,
        opinion_id: disputed_opinion.id
      })

      [card] =
        StatementQueries.get_opinion_cards_by_recency(limit: 20)
        |> Enum.filter(&(&1.statement.id == statement.id))

      assert card.vote.opinion.id == verified_opinion.id
    end

    test "uses aggregate verified opinions before quote-only verified opinions" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 8)

      aggregate_author = author_fixture()

      aggregate_opinion =
        opinion_fixture(%{
          author_id: aggregate_author.id,
          content: "Aggregate verified home quote",
          verification_status: :ai_verified,
          likes_count: 0
        })

      {:ok, _} = Opinions.add_opinion_to_statement(aggregate_opinion, statement.id)
      verify_relevance(aggregate_opinion, statement)

      aggregate_vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: aggregate_author.id,
          opinion_id: aggregate_opinion.id,
          verification_status: :ai_verified
        })

      quote_only_author = author_fixture()

      quote_only_opinion =
        opinion_fixture(%{
          author_id: quote_only_author.id,
          content: "Newer quote-only verified home quote",
          verification_status: :verified,
          likes_count: 10
        })

      {:ok, _} = Opinions.add_opinion_to_statement(quote_only_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: quote_only_author.id,
        opinion_id: quote_only_opinion.id
      })

      [card] =
        StatementQueries.get_opinion_cards_by_recency(limit: 20)
        |> Enum.filter(&(&1.statement.id == statement.id))

      assert card.vote.id == aggregate_vote.id
    end
  end

  describe "get_top_votes_by_answer_for_statements/2" do
    test "uses positive verified opinions before newer disputed opinions in recency mode" do
      statement = statement_fixture()

      verified_author = author_fixture()

      verified_opinion =
        opinion_fixture(%{
          author_id: verified_author.id,
          content: "Older verified answer quote",
          verification_status: :verified
        })

      {:ok, _} = Opinions.add_opinion_to_statement(verified_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: verified_author.id,
        opinion_id: verified_opinion.id,
        answer: :for
      })

      disputed_author = author_fixture()

      disputed_opinion =
        opinion_fixture(%{
          author_id: disputed_author.id,
          content: "Newer disputed answer quote",
          verification_status: :disputed
        })

      {:ok, _} = Opinions.add_opinion_to_statement(disputed_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: disputed_author.id,
        opinion_id: disputed_opinion.id,
        answer: :for
      })

      votes_by_answer =
        StatementQueries.get_top_votes_by_answer_for_statements([statement.id],
          order_by: :recency
        )

      assert votes_by_answer[statement.id][:for].opinion.id == verified_opinion.id
    end

    test "uses aggregate verified opinions before quote-only verified opinions" do
      statement = statement_fixture()

      aggregate_author = author_fixture()

      aggregate_opinion =
        opinion_fixture(%{
          author_id: aggregate_author.id,
          content: "Aggregate verified answer quote",
          verification_status: :ai_verified,
          likes_count: 0
        })

      {:ok, _} = Opinions.add_opinion_to_statement(aggregate_opinion, statement.id)
      verify_relevance(aggregate_opinion, statement)

      aggregate_vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: aggregate_author.id,
          opinion_id: aggregate_opinion.id,
          answer: :for,
          verification_status: :ai_verified
        })

      quote_only_author = author_fixture()

      quote_only_opinion =
        opinion_fixture(%{
          author_id: quote_only_author.id,
          content: "Newer quote-only verified answer quote",
          verification_status: :verified,
          likes_count: 10
        })

      {:ok, _} = Opinions.add_opinion_to_statement(quote_only_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: quote_only_author.id,
        opinion_id: quote_only_opinion.id,
        answer: :for
      })

      votes_by_answer =
        StatementQueries.get_top_votes_by_answer_for_statements([statement.id],
          order_by: :recency
        )

      assert votes_by_answer[statement.id][:for].id == aggregate_vote.id
    end
  end
end
