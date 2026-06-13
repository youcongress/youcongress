defmodule YouCongress.Workers.EnqueueQuoteVerificationsWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.OpinionsFixtures

  alias YouCongress.Workers.EnqueueQuoteVerificationsWorker
  alias YouCongress.Workers.VerificationWorker

  describe "perform/1" do
    test "enqueues a verification job for every sourced quote when no limit is given" do
      quote1 = opinion_fixture(%{source_url: "https://example.com/quote-1"})
      quote2 = opinion_fixture(%{source_url: "https://example.com/quote-2"})
      plain_opinion = opinion_fixture(%{source_url: nil})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = EnqueueQuoteVerificationsWorker.perform(%Oban.Job{args: %{}})
      end)

      assert_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => quote1.id}
      )

      assert_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => quote2.id}
      )

      refute_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => plain_opinion.id}
      )
    end

    test "enqueues at most the requested number of sourced quote verification jobs" do
      quote1 = opinion_fixture(%{source_url: "https://example.com/quote-1"})
      quote2 = opinion_fixture(%{source_url: "https://example.com/quote-2"})
      quote3 = opinion_fixture(%{source_url: "https://example.com/quote-3"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 EnqueueQuoteVerificationsWorker.perform(%Oban.Job{args: %{"limit" => 2}})
      end)

      assert_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => quote1.id}
      )

      assert_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => quote2.id}
      )

      refute_enqueued(
        worker: VerificationWorker,
        args: %{"subject" => "quote", "id" => quote3.id}
      )
    end
  end
end
