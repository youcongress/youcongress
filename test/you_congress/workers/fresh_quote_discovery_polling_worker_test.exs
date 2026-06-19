defmodule YouCongress.Workers.FreshQuoteDiscoveryPollingWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures

  alias YouCongress.Opinions
  alias YouCongress.Workers.FreshQuoteDiscoveryPollingWorker
  alias YouCongress.Workers.MatchQuoteStatementsWorker

  defp put_env_restore(key, value) do
    original = Application.fetch_env(:you_congress, key)
    Application.put_env(:you_congress, key, value)

    on_exit(fn ->
      case original do
        {:ok, original_value} -> Application.put_env(:you_congress, key, original_value)
        :error -> Application.delete_env(:you_congress, key)
      end
    end)
  end

  defp candidate(attrs \\ %{}) do
    Map.merge(
      %{
        "quote" =>
          "AI is changing jobs quickly, and governments should help workers adapt while holding deployers accountable.",
        "source_url" => "https://example.com/fresh-ai-jobs",
        "date" => Date.utc_today() |> Date.to_iso8601(),
        "date_precision" => "day",
        "author" => %{
          "name" => "Fresh AI Author",
          "bio" => "AI policy expert",
          "wikipedia_url" => "https://en.wikipedia.org/wiki/Fresh_AI_Author",
          "twitter_username" => "freshaiauthor"
        },
        "validation_note" => "Source contains quote, attribution, and date."
      },
      attrs
    )
  end

  defp perform_with_quotes(quotes) do
    user = user_fixture()

    put_env_restore(
      :fresh_quote_finder_test_status,
      {:ok, :completed, %{quotes: quotes}}
    )

    Oban.Testing.with_testing_mode(:manual, fn ->
      FreshQuoteDiscoveryPollingWorker.perform(%Oban.Job{
        args: %{"job_id" => "fresh-job-1", "user_id" => user.id, "limit" => 1}
      })
    end)
  end

  describe "perform/1" do
    test "saves a valid fresh quote and enqueues statement matching" do
      assert :ok = perform_with_quotes([candidate()])

      opinion = Opinions.get_by(content: candidate()["quote"], preload: :author)
      assert opinion.source_url == candidate()["source_url"]
      assert opinion.twin == false
      assert opinion.date == Date.utc_today()
      assert opinion.date_precision == :day
      assert opinion.author.name == "Fresh AI Author"

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => opinion.id}
      )
    end

    test "keeps a saved quote even before any statement match exists" do
      assert :ok = perform_with_quotes([candidate()])

      opinion = Opinions.get_by(content: candidate()["quote"], preload: :statements)
      assert opinion.source_url == candidate()["source_url"]
      assert opinion.statements == []
    end

    test "saves a quote when the author name already has multiple rows" do
      first_author = author_fixture(name: "Brad Smith", twitter_username: "brad_smith_one")
      _second_author = author_fixture(name: "Brad Smith", twitter_username: "brad_smith_two")

      quote =
        candidate(%{
          "source_url" => "https://example.com/brad-smith-ai",
          "author" => %{
            "name" => "Brad Smith",
            "bio" => "Technology executive",
            "wikipedia_url" => "",
            "twitter_username" => ""
          }
        })

      assert :ok = perform_with_quotes([quote])

      opinion = Opinions.get_by(content: quote["quote"], preload: :author)
      assert opinion.author.id == first_author.id

      assert_enqueued(
        worker: MatchQuoteStatementsWorker,
        args: %{"opinion_id" => opinion.id}
      )
    end

    test "skips duplicate source URLs" do
      existing = opinion_fixture(%{source_url: "https://example.com/fresh-ai-jobs"})

      assert :ok = perform_with_quotes([candidate()])

      assert Opinions.count(source_url: existing.source_url) == 1
      refute_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "skips duplicate normalized quote content" do
      opinion_fixture(%{
        content:
          "AI is changing jobs quickly, and governments should help workers adapt while holding deployers accountable.",
        source_url: "https://example.com/original-ai-jobs"
      })

      duplicate =
        candidate(%{
          "quote" =>
            "  ai is changing jobs quickly, and governments should help workers adapt while holding deployers accountable.  ",
          "source_url" => "https://example.com/duplicate-ai-jobs"
        })

      assert :ok = perform_with_quotes([duplicate])

      assert Opinions.count(only_quotes: true) == 1
      refute_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "skips obvious author phrase duplicates" do
      author =
        author_fixture(%{
          name: "Fresh AI Author",
          wikipedia_url: "https://en.wikipedia.org/wiki/Fresh_AI_Author"
        })

      opinion_fixture(%{
        author_id: author.id,
        content:
          "AI is changing jobs quickly, and governments should help workers adapt while holding deployers accountable. A second sentence makes it longer.",
        source_url: "https://example.com/original-ai-jobs"
      })

      duplicate =
        candidate(%{
          "quote" =>
            "AI is changing jobs quickly, and governments should help workers adapt while holding deployers accountable in this new era.",
          "source_url" => "https://example.com/near-duplicate-ai-jobs"
        })

      assert :ok = perform_with_quotes([duplicate])

      assert Opinions.count(only_quotes: true) == 1
      refute_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "saves candidates published within the last week" do
      recent_date = Date.utc_today() |> Date.add(-6) |> Date.to_iso8601()

      assert :ok =
               perform_with_quotes([
                 candidate(%{
                   "date" => recent_date,
                   "source_url" => "https://example.com/week-old-ai-jobs"
                 })
               ])

      assert Opinions.count(only_quotes: true) == 1
      assert_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "skips candidates older than one week" do
      old_date = Date.utc_today() |> Date.add(-8) |> Date.to_iso8601()

      assert :ok = perform_with_quotes([candidate(%{"date" => old_date})])

      assert Opinions.count(only_quotes: true) == 0
      refute_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "skips candidates with missing required fields" do
      assert :ok = perform_with_quotes([candidate(%{"source_url" => ""})])
      assert Opinions.count(only_quotes: true) == 0
      refute_enqueued(worker: MatchQuoteStatementsWorker)

      assert :ok = perform_with_quotes([candidate(%{"author" => %{"name" => ""}})])
      assert Opinions.count(only_quotes: true) == 0
      refute_enqueued(worker: MatchQuoteStatementsWorker)
    end

    test "snoozes while the OpenAI job is still in progress" do
      put_env_restore(:fresh_quote_finder_test_status, {:ok, :in_progress})

      assert {:snooze, 60} =
               FreshQuoteDiscoveryPollingWorker.perform(%Oban.Job{
                 args: %{"job_id" => "fresh-job-1", "user_id" => user_fixture().id}
               })
    end

    test "stores saved quote details in the Oban job metadata" do
      user = user_fixture()

      put_env_restore(
        :fresh_quote_finder_test_status,
        {:ok, :completed, %{quotes: [candidate()]}}
      )

      {:ok, job} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          %{"job_id" => "fresh-job-1", "user_id" => user.id, "limit" => 1}
          |> FreshQuoteDiscoveryPollingWorker.new()
          |> Oban.insert()
        end)

      assert :ok =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 FreshQuoteDiscoveryPollingWorker.perform(job)
               end)

      result = YouCongress.Repo.reload!(job).meta["fresh_quote_discovery"]

      assert %{
               "status" => "completed",
               "outcome" => "all_considered_quotes_saved",
               "discovered_count" => 1,
               "considered_count" => 1,
               "saved_count" => 1,
               "skipped_count" => 0,
               "skipped_candidates" => []
             } = result

      assert [opinion_id] = result["saved_opinion_ids"]
      assert Opinions.get_opinion!(opinion_id)
    end

    test "stores why a quote wasn't saved in the Oban job metadata" do
      existing = opinion_fixture(%{source_url: candidate()["source_url"]})
      user = user_fixture()

      put_env_restore(
        :fresh_quote_finder_test_status,
        {:ok, :completed, %{quotes: [candidate()]}}
      )

      {:ok, job} =
        Oban.Testing.with_testing_mode(:manual, fn ->
          %{"job_id" => "fresh-job-1", "user_id" => user.id, "limit" => 1}
          |> FreshQuoteDiscoveryPollingWorker.new()
          |> Oban.insert()
        end)

      assert :ok =
               Oban.Testing.with_testing_mode(:manual, fn ->
                 FreshQuoteDiscoveryPollingWorker.perform(job)
               end)

      assert %{
               "status" => "completed",
               "outcome" => "no_quote_saved",
               "saved_count" => 0,
               "saved_opinion_ids" => [],
               "skipped_count" => 1,
               "skipped_candidates" => [
                 %{
                   "candidate_index" => 0,
                   "outcome" => "skipped",
                   "reason" => "duplicate_source_url"
                 }
               ]
             } = YouCongress.Repo.reload!(job).meta["fresh_quote_discovery"]

      assert Opinions.count(source_url: existing.source_url) == 1
    end
  end
end
