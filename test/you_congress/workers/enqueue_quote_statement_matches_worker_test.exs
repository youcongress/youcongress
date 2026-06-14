defmodule YouCongress.Workers.EnqueueQuoteStatementMatchesWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.OpinionsFixtures

  alias YouCongress.Workers.EnqueueQuoteStatementMatchesWorker
  alias YouCongress.Workers.MatchQuoteStatementsWorker

  describe "perform/1" do
    test "enqueues a statement matching job for every sourced quote when no limit is given" do
      quote1 = opinion_fixture(%{source_url: "https://example.com/quote-1"})
      quote2 = opinion_fixture(%{source_url: "https://example.com/quote-2"})
      plain_opinion = opinion_fixture(%{source_url: nil})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueQuoteStatementMatchesWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => quote1.id}
      )

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => quote2.id}
      )

      refute_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => plain_opinion.id}
      )
    end

    test "enqueues at most the requested number of sourced quote matching jobs" do
      quote1 = opinion_fixture(%{source_url: "https://example.com/quote-1"})
      quote2 = opinion_fixture(%{source_url: "https://example.com/quote-2"})
      quote3 = opinion_fixture(%{source_url: "https://example.com/quote-3"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 EnqueueQuoteStatementMatchesWorker.perform(%Oban.Job{
                   args: %{"limit" => 2}
                 })
      end)

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => quote1.id}
      )

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => quote2.id}
      )

      refute_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => quote3.id}
      )
    end
  end
end
