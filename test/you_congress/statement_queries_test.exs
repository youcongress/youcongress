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
    test "only returns statements with at least 15 opinions" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 14)

      refute Enum.any?(
               StatementQueries.get_opinion_cards_by_recency(limit: 20),
               &(&1.statement.id == statement.id)
             )

      refute Enum.any?(
               StatementQueries.get_opinion_cards_by_top_likes(limit: 20),
               &(&1.statement.id == statement.id)
             )

      refute Enum.any?(
               StatementQueries.get_opinion_cards_by_quote_date(limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_recency(min_opinions: 14, limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_top_likes(min_opinions: 14, limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_quote_date(min_opinions: 14, limit: 20),
               &(&1.statement.id == statement.id)
             )

      fill_statement_with_quotes(statement.id, 1)

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_recency(limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_top_likes(limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert Enum.any?(
               StatementQueries.get_opinion_cards_by_quote_date(limit: 20),
               &(&1.statement.id == statement.id)
             )
    end

    test "min_opinions zero includes statements without opinions" do
      statement = statement_fixture()

      refute Enum.any?(
               StatementQueries.get_opinion_cards_by_recency(limit: 20),
               &(&1.statement.id == statement.id)
             )

      assert [
               %{statement: %{id: statement_id}, vote: nil}
             ] = StatementQueries.get_opinion_cards_by_recency(min_opinions: 0, limit: 20)

      assert statement_id == statement.id

      assert [
               %{statement: %{id: statement_id}, vote: nil}
             ] = StatementQueries.get_opinion_cards_by_quote_date(min_opinions: 0, limit: 20)

      assert statement_id == statement.id

      assert [
               %{statement: %{id: statement_id}, vote: nil}
             ] = StatementQueries.get_opinion_cards_by_top_likes(min_opinions: 0, limit: 20)

      assert statement_id == statement.id
    end

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
      fill_statement_with_quotes(statement.id, 18)

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
      fill_statement_with_quotes(statement.id, 18)

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

    test "uses the most recently added quote regardless of quote date" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 18)

      older_author = author_fixture()

      older_opinion =
        opinion_fixture(%{
          author_id: older_author.id,
          content: "Older high-like verified home quote",
          verification_status: :verified,
          likes_count: 25,
          date: ~D[2025-01-01],
          date_precision: :year
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: older_author.id,
        opinion_id: older_opinion.id
      })

      newer_author = author_fixture()

      newer_opinion =
        opinion_fixture(%{
          author_id: newer_author.id,
          content: "Newer low-like verified home quote",
          verification_status: :ai_verified,
          likes_count: 0,
          date: ~D[2020-01-01],
          date_precision: :year
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_opinion, statement.id)

      newer_vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: newer_author.id,
          opinion_id: newer_opinion.id
        })

      [card] =
        StatementQueries.get_opinion_cards_by_recency(limit: 20)
        |> Enum.filter(&(&1.statement.id == statement.id))

      assert card.vote.id == newer_vote.id
    end

    test "orders statements by newest opinion id regardless of quote date" do
      older_statement = statement_fixture()
      fill_statement_with_quotes(older_statement.id, 19)
      older_author = author_fixture()

      older_opinion =
        opinion_fixture(%{
          author_id: older_author.id,
          verification_status: :ai_verified,
          date: ~D[2026-06-18],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_opinion, older_statement.id)
      verify_relevance(older_opinion, older_statement)

      vote_fixture(%{
        statement_id: older_statement.id,
        author_id: older_author.id,
        opinion_id: older_opinion.id,
        verification_status: :ai_verified
      })

      newer_statement = statement_fixture()
      fill_statement_with_quotes(newer_statement.id, 19)
      newer_author = author_fixture()

      newer_opinion =
        opinion_fixture(%{
          author_id: newer_author.id,
          verification_status: :ai_verified,
          date: ~D[2020-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_opinion, newer_statement.id)
      verify_relevance(newer_opinion, newer_statement)

      vote_fixture(%{
        statement_id: newer_statement.id,
        author_id: newer_author.id,
        opinion_id: newer_opinion.id,
        verification_status: :ai_verified
      })

      statement_ids =
        StatementQueries.get_opinion_cards_by_recency(limit: 20)
        |> Enum.map(& &1.statement.id)

      assert statement_ids == [newer_statement.id, older_statement.id]
    end
  end

  describe "get_opinion_cards_by_quote_date/1" do
    test "orders statements by newest quote date instead of newest opinion id" do
      newer_date_statement = statement_fixture()
      fill_statement_with_quotes(newer_date_statement.id, 19)
      newer_date_author = author_fixture()

      newer_date_opinion =
        opinion_fixture(%{
          author_id: newer_date_author.id,
          verification_status: :ai_verified,
          date: ~D[2026-06-18],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_date_opinion, newer_date_statement.id)
      verify_relevance(newer_date_opinion, newer_date_statement)

      vote_fixture(%{
        statement_id: newer_date_statement.id,
        author_id: newer_date_author.id,
        opinion_id: newer_date_opinion.id,
        verification_status: :ai_verified
      })

      older_date_statement = statement_fixture()
      fill_statement_with_quotes(older_date_statement.id, 19)
      older_date_author = author_fixture()

      older_date_opinion =
        opinion_fixture(%{
          author_id: older_date_author.id,
          verification_status: :ai_verified,
          date: ~D[2020-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_date_opinion, older_date_statement.id)
      verify_relevance(older_date_opinion, older_date_statement)

      vote_fixture(%{
        statement_id: older_date_statement.id,
        author_id: older_date_author.id,
        opinion_id: older_date_opinion.id,
        verification_status: :ai_verified
      })

      statement_ids =
        StatementQueries.get_opinion_cards_by_quote_date(limit: 20)
        |> Enum.map(& &1.statement.id)

      assert statement_ids == [newer_date_statement.id, older_date_statement.id]
    end

    test "places undated quotes after dated quotes" do
      dated_statement = statement_fixture()
      fill_statement_with_quotes(dated_statement.id, 19)
      dated_author = author_fixture()

      dated_opinion =
        opinion_fixture(%{
          author_id: dated_author.id,
          verification_status: :ai_verified,
          date: ~D[2020-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(dated_opinion, dated_statement.id)
      verify_relevance(dated_opinion, dated_statement)

      vote_fixture(%{
        statement_id: dated_statement.id,
        author_id: dated_author.id,
        opinion_id: dated_opinion.id,
        verification_status: :ai_verified
      })

      undated_statement = statement_fixture()
      fill_statement_with_quotes(undated_statement.id, 19)
      undated_author = author_fixture()

      undated_opinion =
        opinion_fixture(%{
          author_id: undated_author.id,
          verification_status: :ai_verified
        })

      {:ok, _} = Opinions.add_opinion_to_statement(undated_opinion, undated_statement.id)
      verify_relevance(undated_opinion, undated_statement)

      vote_fixture(%{
        statement_id: undated_statement.id,
        author_id: undated_author.id,
        opinion_id: undated_opinion.id,
        verification_status: :ai_verified
      })

      statement_ids =
        StatementQueries.get_opinion_cards_by_quote_date(limit: 20)
        |> Enum.map(& &1.statement.id)

      assert statement_ids == [dated_statement.id, undated_statement.id]
    end
  end

  describe "get_top_votes_by_answer_for_statements/2" do
    test "uses quote dates in quote date mode" do
      statement = statement_fixture()

      newer_date_author = author_fixture()

      newer_date_opinion =
        opinion_fixture(%{
          author_id: newer_date_author.id,
          content: "Newer dated answer quote",
          verification_status: :verified,
          date: ~D[2026-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_date_opinion, statement.id)

      newer_date_vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: newer_date_author.id,
          opinion_id: newer_date_opinion.id,
          answer: :for
        })

      older_date_author = author_fixture()

      older_date_opinion =
        opinion_fixture(%{
          author_id: older_date_author.id,
          content: "Older but later added answer quote",
          verification_status: :verified,
          date: ~D[2020-01-01],
          date_precision: :day
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_date_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: older_date_author.id,
        opinion_id: older_date_opinion.id,
        answer: :for
      })

      votes_by_answer =
        StatementQueries.get_top_votes_by_answer_for_statements([statement.id],
          order_by: :quote_date
        )

      assert votes_by_answer[statement.id][:for].id == newer_date_vote.id
    end

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

    test "uses the most recently added quote regardless of quote date" do
      statement = statement_fixture()

      older_author = author_fixture()

      older_opinion =
        opinion_fixture(%{
          author_id: older_author.id,
          content: "Older high-like verified answer quote",
          verification_status: :verified,
          likes_count: 25,
          date: ~D[2025-01-01],
          date_precision: :year
        })

      {:ok, _} = Opinions.add_opinion_to_statement(older_opinion, statement.id)

      vote_fixture(%{
        statement_id: statement.id,
        author_id: older_author.id,
        opinion_id: older_opinion.id,
        answer: :for
      })

      newer_author = author_fixture()

      newer_opinion =
        opinion_fixture(%{
          author_id: newer_author.id,
          content: "Newer low-like verified answer quote",
          verification_status: :ai_verified,
          likes_count: 0,
          date: ~D[2020-01-01],
          date_precision: :year
        })

      {:ok, _} = Opinions.add_opinion_to_statement(newer_opinion, statement.id)

      newer_vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: newer_author.id,
          opinion_id: newer_opinion.id,
          answer: :for
        })

      votes_by_answer =
        StatementQueries.get_top_votes_by_answer_for_statements([statement.id],
          order_by: :recency
        )

      assert votes_by_answer[statement.id][:for].id == newer_vote.id
    end
  end
end
