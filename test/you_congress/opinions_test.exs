defmodule YouCongress.OpinionsTest do
  use YouCongress.DataCase

  import YouCongress.AccountsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  import Mock

  alias YouCongress.Embeddings
  alias YouCongress.Opinions
  alias YouCongress.Votes

  @embedding_dimensions 1536

  describe "date metadata" do
    test "stores exact dates with day precision by default" do
      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "quoted content",
          source_url: "https://example.com/quote",
          date: "2026-04-13",
          twin: false
        })

      assert opinion.date == ~D[2026-04-13]
      assert opinion.date_precision == :day
    end

    test "normalizes year-only dates to January 1 with year precision" do
      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "quoted content",
          source_url: "https://example.com/quote",
          date: "2026",
          twin: false
        })

      assert opinion.date == ~D[2026-01-01]
      assert opinion.date_precision == :year
    end

    test "truncates stored date to the selected precision" do
      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "quoted content",
          source_url: "https://example.com/quote",
          date: "2026-04-13",
          date_precision: "month",
          twin: false
        })

      assert opinion.date == ~D[2026-04-01]
      assert opinion.date_precision == :month
    end
  end

  describe "content_embedding" do
    test "generates an embedding when a sourced quote is created" do
      embedding = embedding([1.0, 0.5, -0.25])

      with_mock Embeddings, embed: fn "quoted content" -> {:ok, embedding} end do
        {:ok, %{opinion: opinion}} =
          Opinions.create_opinion(%{
            content: "quoted content",
            source_url: "https://example.com/quote",
            twin: false
          })

        opinion = Opinions.get_opinion!(opinion.id)

        assert Pgvector.to_list(opinion.content_embedding) == embedding
      end
    end

    test "stores opinion content embeddings" do
      embedding = embedding([1.0, 0.5, -0.25])

      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "quoted content",
          content_embedding: embedding,
          source_url: "https://example.com/quote",
          twin: false
        })

      opinion = Opinions.get_opinion!(opinion.id)

      assert Pgvector.to_list(opinion.content_embedding) == embedding
    end

    test "updates the embedding when sourced quote content changes" do
      old_embedding = embedding([1.0, 0.0, 0.0])
      new_embedding = embedding([0.0, 1.0, 0.0])

      opinion =
        opinion_fixture(%{
          content: "old quoted content",
          content_embedding: old_embedding,
          source_url: "https://example.com/quote"
        })

      with_mock Embeddings, embed: fn "updated quoted content" -> {:ok, new_embedding} end do
        {:ok, opinion} =
          Opinions.update_opinion(opinion, %{
            content: "updated quoted content"
          })

        assert Pgvector.to_list(opinion.content_embedding) == new_embedding
      end
    end

    test "clears a stale embedding when quote content changes and embedding generation fails" do
      old_embedding = embedding([1.0, 0.0, 0.0])

      opinion =
        opinion_fixture(%{
          content: "old quoted content",
          content_embedding: old_embedding,
          source_url: "https://example.com/quote"
        })

      with_mock Embeddings, embed: fn "updated quoted content" -> {:error, :boom} end do
        {:ok, opinion} =
          Opinions.update_opinion(opinion, %{
            content: "updated quoted content"
          })

        assert opinion.content_embedding == nil
      end
    end

    test "clears the embedding when a quote source URL is removed" do
      opinion =
        opinion_fixture(%{
          content_embedding: embedding([1.0, 0.0, 0.0]),
          source_url: "https://example.com/quote"
        })

      {:ok, opinion} = Opinions.update_opinion(opinion, %{source_url: nil})

      assert opinion.source_url == nil
      assert opinion.content_embedding == nil
    end
  end

  describe "get_opinion/1" do
    test "honors descending id order when filtering opinions with statements" do
      user = user_fixture()
      statement = statement_fixture()

      {:ok, %{opinion: older_quote}} =
        Opinions.create_opinion(%{
          content: "older quote",
          source_url: "https://example.com/older",
          twin: false,
          user_id: user.id
        })

      {:ok, %{opinion: newer_quote}} =
        Opinions.create_opinion(%{
          content: "newer quote",
          source_url: "https://example.com/newer",
          twin: false,
          user_id: user.id
        })

      {:ok, %{opinion: _unlinked_quote}} =
        Opinions.create_opinion(%{
          content: "unlinked quote",
          source_url: "https://example.com/unlinked",
          twin: false,
          user_id: user.id
        })

      assert {:ok, _} = Opinions.add_opinion_to_statement(older_quote, statement, user.id)
      assert {:ok, _} = Opinions.add_opinion_to_statement(newer_quote, statement, user.id)

      assert %{} =
               opinion =
               Opinions.get_opinion(
                 has_statements: true,
                 only_quotes: true,
                 is_verified: false,
                 order_by: [desc: :id]
               )

      assert opinion.id == newer_quote.id
    end
  end

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

    test "keeps one vote and updates it to a newly linked sourced quote" do
      older_quote = opinion_fixture(%{twin: false})
      newer_quote = opinion_fixture(%{author_id: older_quote.author_id, twin: false})
      statement = statement_fixture()

      assert {:ok, _} = Opinions.add_opinion_to_statement(older_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: older_quote.author_id,
          opinion_id: older_quote.id,
          answer: :for
        })

      assert {:ok, _} = Opinions.add_opinion_to_statement(newer_quote, statement)

      vote = Votes.get_vote(vote.id)
      assert vote.opinion_id == newer_quote.id
      assert Votes.count_by(statement_id: statement.id) == 1

      older_quote = Opinions.get_opinion!(older_quote.id, preload: [:statements])
      newer_quote = Opinions.get_opinion!(newer_quote.id, preload: [:statements])

      assert Enum.map(older_quote.statements, & &1.id) == [statement.id]
      assert Enum.map(newer_quote.statements, & &1.id) == [statement.id]
    end
  end

  describe "delete_opinion/1" do
    test "deletes current quote votes when no replacement quote exists" do
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
          answer: :for,
          opinion_id: quote.id
        })

      inferred_vote_2 =
        vote_fixture(%{
          statement_id: statement_2.id,
          author_id: quote.author_id,
          answer: :against,
          opinion_id: quote.id
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

    test "keeps vote unchanged when deleting an older linked quote" do
      older_quote = opinion_fixture(%{twin: false})
      current_quote = opinion_fixture(%{author_id: older_quote.author_id, twin: false})
      statement = statement_fixture()

      assert {:ok, _} = Opinions.add_opinion_to_statement(older_quote, statement)
      assert {:ok, _} = Opinions.add_opinion_to_statement(current_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: older_quote.author_id,
          opinion_id: current_quote.id,
          answer: :for
        })

      assert {:ok, _deleted_quote} = Opinions.delete_opinion(older_quote)

      assert Votes.get_vote(vote.id).opinion_id == current_quote.id
    end

    test "reassigns vote by most recent quote date when deleting the current quote" do
      high_date_quote =
        opinion_fixture(%{twin: false, date: ~D[2025-01-01], date_precision: :year})

      higher_id_quote =
        opinion_fixture(%{
          author_id: high_date_quote.author_id,
          twin: false,
          date: ~D[2020-01-01],
          date_precision: :year
        })

      current_quote =
        opinion_fixture(%{
          author_id: high_date_quote.author_id,
          twin: false,
          date: ~D[2030-01-01],
          date_precision: :year
        })

      statement = statement_fixture()

      assert {:ok, _} = Opinions.add_opinion_to_statement(high_date_quote, statement)
      assert {:ok, _} = Opinions.add_opinion_to_statement(higher_id_quote, statement)
      assert {:ok, _} = Opinions.add_opinion_to_statement(current_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: high_date_quote.author_id,
          opinion_id: current_quote.id,
          answer: :for
        })

      assert {:ok, _deleted_quote} = Opinions.delete_opinion(current_quote)

      assert Votes.get_vote(vote.id).opinion_id == high_date_quote.id
    end

    test "keeps author votes for non-quote opinions on delete" do
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

  describe "remove_opinion_from_statement/2" do
    test "deletes the vote when removing its current quote and no replacement exists" do
      quote_opinion = opinion_fixture(%{twin: false})
      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(quote_opinion, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: quote_opinion.author_id,
          answer: :for,
          opinion_id: quote_opinion.id
        })

      assert {:ok, _} = Opinions.remove_opinion_from_statement(quote_opinion, statement)

      assert Votes.get_vote(vote.id) == nil

      %{statements: statements} = Opinions.get_opinion!(quote_opinion.id, preload: [:statements])
      assert statements == []
    end

    test "keeps the vote when removing an older linked quote" do
      older_quote = opinion_fixture(%{twin: false})
      current_quote = opinion_fixture(%{author_id: older_quote.author_id, twin: false})
      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(older_quote, statement)
      {:ok, _} = Opinions.add_opinion_to_statement(current_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: older_quote.author_id,
          answer: :for,
          opinion_id: current_quote.id
        })

      assert {:ok, _} = Opinions.remove_opinion_from_statement(older_quote, statement)

      assert Votes.get_vote(vote.id).opinion_id == current_quote.id
    end

    test "reassigns the vote by highest id when removing the current quote and dates tie" do
      lower_id_quote =
        opinion_fixture(%{twin: false, date: ~D[2025-01-01], date_precision: :year})

      higher_id_quote =
        opinion_fixture(%{
          author_id: lower_id_quote.author_id,
          twin: false,
          date: ~D[2025-01-01],
          date_precision: :year
        })

      current_quote =
        opinion_fixture(%{
          author_id: lower_id_quote.author_id,
          twin: false,
          date: ~D[2030-01-01],
          date_precision: :year
        })

      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(lower_id_quote, statement)
      {:ok, _} = Opinions.add_opinion_to_statement(higher_id_quote, statement)
      {:ok, _} = Opinions.add_opinion_to_statement(current_quote, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: lower_id_quote.author_id,
          answer: :for,
          opinion_id: current_quote.id
        })

      assert {:ok, _} = Opinions.remove_opinion_from_statement(current_quote, statement)

      assert Votes.get_vote(vote.id).opinion_id == higher_id_quote.id
    end

    test "keeps the vote when opinion has no source_url" do
      opinion = opinion_fixture(%{source_url: nil, twin: false})
      statement = statement_fixture()

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement)

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: opinion.author_id,
          answer: :for
        })

      assert {:ok, _} = Opinions.remove_opinion_from_statement(opinion, statement)

      assert Votes.get_vote(vote.id) != nil
    end

    test "returns not_associated when no link exists" do
      opinion = opinion_fixture()
      statement = statement_fixture()

      assert {:error, :not_associated} =
               Opinions.remove_opinion_from_statement(opinion, statement)
    end
  end

  defp embedding(values) do
    values ++ List.duplicate(0.0, @embedding_dimensions - length(values))
  end
end
