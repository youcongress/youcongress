defmodule YouCongress.Statements.QuotesCsvTest do
  use YouCongress.DataCase

  alias NimbleCSV.RFC4180, as: CSV

  alias YouCongress.Cache
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.Statements.QuotesCsv
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongress.VoteVerifications

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  # A statement with one author whose vote points at `quote`. Returns everything
  # needed to attach further quotes or verifications.
  defp setup_statement do
    user = user_fixture()
    author = author_fixture()
    statement = statement_fixture()
    opinion = add_quote(statement, author, user, "Main quote content")

    {:ok, vote} =
      Votes.create_vote(%{
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: :for
      })

    %{user: user, author: author, statement: statement, opinion: opinion, vote: vote}
  end

  defp add_quote(statement, author, user, content) do
    opinion =
      opinion_fixture(%{
        author_id: author.id,
        user_id: user.id,
        content: content,
        source_url: "https://example.com/source"
      })

    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)
    opinion
  end

  defp verify_quote(opinion, user, status, model \\ "human") do
    {:ok, _} =
      Verifications.create_verification(%{
        opinion_id: opinion.id,
        user_id: user.id,
        status: status,
        model: model
      })
  end

  defp verify_relevance(opinion, statement, user, status, model \\ "human") do
    os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

    {:ok, _} =
      OpinionStatementVerifications.create_verification(%{
        opinion_statement_id: os.id,
        user_id: user.id,
        status: status,
        model: model
      })
  end

  defp verify_vote(vote, opinion, user, status, model \\ "human") do
    {:ok, _} =
      VoteVerifications.create_verification(%{
        vote_id: vote.id,
        opinion_id: opinion.id,
        user_id: user.id,
        status: status,
        model: model
      })
  end

  defp verify_pipeline(ctx, opinion, status, model \\ "human") do
    verify_quote(opinion, ctx.user, status, model)
    verify_relevance(opinion, ctx.statement, ctx.user, status, model)
    verify_vote(ctx.vote, opinion, ctx.user, status, model)
  end

  # Parsed data rows (skipping the two license rows and the header row).
  defp csv_rows(statement) do
    Cache.delete({:statement_csv, statement.id})

    statement
    |> QuotesCsv.generate()
    |> CSV.parse_string(skip_headers: false)
    |> Enum.drop(3)
  end

  defp quote_column(row), do: Enum.at(row, 10)
  defp quote_verification_status(row), do: Enum.at(row, 16)

  test "exports a fully verified quote" do
    ctx = setup_statement()
    verify_pipeline(ctx, ctx.opinion, :verified)

    assert [row] = csv_rows(ctx.statement)
    assert quote_column(row) == "Main quote content"
    assert quote_verification_status(row) == "verified"
  end

  test "excludes quotes whose pipeline is not fully positive" do
    ctx = setup_statement()
    # Quote authenticity verified, but relevance and vote answer still pending.
    verify_quote(ctx.opinion, ctx.user, :verified)

    assert csv_rows(ctx.statement) == []
  end

  test "exports verified quotes even when the author's vote points at another quote" do
    ctx = setup_statement()
    verify_pipeline(ctx, ctx.opinion, :verified)

    # Second quote by the same author on the same statement; the vote still
    # points at the first one, so this is an "alternate" quote.
    alternate = add_quote(ctx.statement, ctx.author, ctx.user, "Alternate quote content")
    verify_pipeline(ctx, alternate, :ai_verified, "gpt-test")

    contents = ctx.statement |> csv_rows() |> Enum.map(&quote_column/1)
    assert "Main quote content" in contents
    assert "Alternate quote content" in contents
  end

  test "an unverified alternate quote is not exported" do
    ctx = setup_statement()
    verify_pipeline(ctx, ctx.opinion, :verified)
    add_quote(ctx.statement, ctx.author, ctx.user, "Unverified alternate")

    assert [row] = csv_rows(ctx.statement)
    assert quote_column(row) == "Main quote content"
  end

  test "only the last verification of each kind matters" do
    ctx = setup_statement()
    verify_quote(ctx.opinion, ctx.user, :disputed)
    verify_quote(ctx.opinion, ctx.user, :verified)
    verify_relevance(ctx.opinion, ctx.statement, ctx.user, :verified)
    verify_vote(ctx.vote, ctx.opinion, ctx.user, :verified)

    assert [row] = csv_rows(ctx.statement)
    assert quote_verification_status(row) == "verified"

    # And the other way around: a later disputed excludes the quote.
    verify_quote(ctx.opinion, ctx.user, :disputed)
    assert csv_rows(ctx.statement) == []
  end

  test "vote verifications stamped for another quote do not leak into a row" do
    ctx = setup_statement()
    verify_pipeline(ctx, ctx.opinion, :verified)

    alternate = add_quote(ctx.statement, ctx.author, ctx.user, "Alternate quote content")
    verify_quote(alternate, ctx.user, :verified)
    verify_relevance(alternate, ctx.statement, ctx.user, :verified)
    # No vote verification for the alternate quote: its pipeline is incomplete.

    assert [row] = csv_rows(ctx.statement)
    assert quote_column(row) == "Main quote content"
  end
end
