defmodule YouCongress.Workers.MatchQuoteStatementsWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import ExUnit.CaptureLog
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongress.Workers.MatchQuoteStatementsPollingWorker
  alias YouCongress.Workers.MatchQuoteStatementsWorker
  alias YouCongress.Workers.VerificationWorker

  defmodule StaticMatcher do
    @behaviour YouCongress.Verifications.QuoteStatementMatcher

    @impl true
    def submit(opinion, statements) do
      send(
        Application.get_env(:you_congress, :quote_statement_matcher_test_pid),
        {:matched, opinion.id, Enum.map(statements, & &1.id)}
      )

      {:ok, "match-job-#{opinion.id}"}
    end

    @impl true
    def check_job_status(_job_id) do
      Application.get_env(
        :you_congress,
        :quote_statement_matcher_test_status,
        {:ok, :completed,
         Application.get_env(:you_congress, :quote_statement_matcher_test_matches, [])}
      )
    end
  end

  defmodule ErrorMatcher do
    @behaviour YouCongress.Verifications.QuoteStatementMatcher

    @impl true
    def submit(_opinion, _statements), do: {:error, :llm_failed}

    @impl true
    def check_job_status(_job_id), do: {:error, :polling_failed}
  end

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

  defp delete_env_restore(key) do
    original = Application.fetch_env(:you_congress, key)
    Application.delete_env(:you_congress, key)

    on_exit(fn ->
      case original do
        {:ok, original_value} -> Application.put_env(:you_congress, key, original_value)
        :error -> Application.delete_env(:you_congress, key)
      end
    end)
  end

  defp use_static_matcher(matches) do
    put_env_restore(:quote_statement_matcher_implementation, StaticMatcher)
    put_env_restore(:quote_statement_matcher_test_pid, self())
    put_env_restore(:quote_statement_matcher_test_matches, matches)
  end

  defp set_system_user do
    user = user_fixture()
    put_env_restore(:verification_user_id, user.id)
    user
  end

  defp sourced_quote(attrs \\ %{}) do
    attrs = Map.new(attrs)
    author = attrs[:author] || author_fixture()
    user = attrs[:user] || user_fixture(%{author_id: author.id})

    opinion_fixture(
      attrs
      |> Map.drop([:author, :user])
      |> Enum.into(%{
        author_id: author.id,
        user_id: user.id,
        source_url: "https://example.com/quote",
        twin: false
      })
    )
  end

  describe "perform/1" do
    test "submits matching in the background and enqueues its polling worker" do
      quote = sourced_quote()
      statement = statement_fixture()
      set_system_user()
      use_static_matcher([])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 MatchQuoteStatementsWorker.perform(%Oban.Job{
                   args: %{"opinion_id" => quote.id}
                 })

        assert_enqueued(
          worker: MatchQuoteStatementsPollingWorker,
          args: %{
            "opinion_id" => quote.id,
            "job_id" => "match-job-#{quote.id}",
            "statement_ids" => [statement.id]
          }
        )
      end)
    end

    test "links matched statements and creates or updates votes with returned answers" do
      author = author_fixture()
      quote = sourced_quote(author: author)
      for_statement = statement_fixture(%{title: "Open source AI should be protected"})
      against_statement = statement_fixture(%{title: "AI development should be banned"})
      set_system_user()

      {:ok, old_vote} =
        Votes.create_vote(%{
          author_id: author.id,
          statement_id: against_statement.id,
          answer: :for
        })

      use_static_matcher([
        %{"statement_id" => for_statement.id, "answer" => "for", "comment" => "supports it"},
        %{
          "statement_id" => "#{against_statement.id}",
          "answer" => "Against",
          "comment" => "opposes it"
        }
      ])

      assert :ok =
               MatchQuoteStatementsWorker.perform(%Oban.Job{
                 args: %{"opinion_id" => quote.id}
               })

      assert_received {:matched, quote_id, statement_ids}
      assert quote_id == quote.id
      assert for_statement.id in statement_ids
      assert against_statement.id in statement_ids

      assert OpinionsStatements.get_opinion_statement(quote.id, for_statement.id)
      assert OpinionsStatements.get_opinion_statement(quote.id, against_statement.id)

      for_vote = Votes.get_by(statement_id: for_statement.id, author_id: author.id)
      assert for_vote.answer == :for
      assert for_vote.opinion_id == quote.id
      assert for_vote.twin == false

      updated_vote = Votes.get_vote!(old_vote.id)
      assert updated_vote.answer == :against
      assert updated_vote.opinion_id == quote.id
      assert updated_vote.twin == false
    end

    test "ignores invalid matches and handles already linked statements" do
      author = author_fixture()
      user = user_fixture(%{author_id: author.id})
      quote = sourced_quote(author: author, user: user)
      linked_statement = statement_fixture(%{title: "AI labs should share safety results"})
      invalid_answer_statement = statement_fixture(%{title: "AI labs should stop all work"})
      set_system_user()

      assert {:ok, _} = Opinions.add_opinion_to_statement(quote, linked_statement, user.id)

      use_static_matcher([
        %{"statement_id" => linked_statement.id, "answer" => "abstain", "comment" => "neutral"},
        %{"statement_id" => invalid_answer_statement.id, "answer" => "maybe", "comment" => "bad"},
        %{"statement_id" => -1, "answer" => "for", "comment" => "missing"}
      ])

      assert :ok =
               MatchQuoteStatementsWorker.perform(%Oban.Job{
                 args: %{"opinion_id" => quote.id}
               })

      assert_received {:matched, quote_id, statement_ids}
      assert quote_id == quote.id
      refute linked_statement.id in statement_ids
      assert invalid_answer_statement.id in statement_ids

      assert OpinionsStatements.get_opinion_statement(quote.id, linked_statement.id)
      refute OpinionsStatements.get_opinion_statement(quote.id, invalid_answer_statement.id)

      refute Votes.get_by(statement_id: linked_statement.id, author_id: author.id)
    end

    test "skips sourced quotes when verification_user_id is not configured" do
      quote = sourced_quote()
      statement_fixture()
      delete_env_restore(:verification_user_id)
      use_static_matcher([%{"statement_id" => 1, "answer" => "for", "comment" => "unused"}])

      assert :ok =
               MatchQuoteStatementsWorker.perform(%Oban.Job{
                 args: %{"opinion_id" => quote.id}
               })

      refute_received {:matched, _quote_id, _statement_ids}
    end

    test "skips plain opinions" do
      plain_opinion = opinion_fixture(%{source_url: nil})
      statement_fixture()
      set_system_user()
      use_static_matcher([%{"statement_id" => 1, "answer" => "for", "comment" => "unused"}])

      assert :ok =
               MatchQuoteStatementsWorker.perform(%Oban.Job{
                 args: %{"opinion_id" => plain_opinion.id}
               })

      refute_received {:matched, _quote_id, _statement_ids}
    end

    test "returns an error when the matcher fails" do
      quote = sourced_quote()
      statement_fixture()
      set_system_user()
      put_env_restore(:quote_statement_matcher_implementation, ErrorMatcher)

      log =
        capture_log(fn ->
          assert {:error, :llm_failed} =
                   MatchQuoteStatementsWorker.perform(%Oban.Job{
                     args: %{"opinion_id" => quote.id}
                   })
        end)

      assert log =~ "Failed to submit statement matching"
    end

    test "polling snoozes in-progress jobs and cancels failed jobs" do
      quote = sourced_quote()
      statement = statement_fixture()
      set_system_user()
      use_static_matcher([])

      job = %Oban.Job{
        args: %{
          "opinion_id" => quote.id,
          "job_id" => "match-job-#{quote.id}",
          "statement_ids" => [statement.id]
        }
      }

      put_env_restore(:quote_statement_matcher_test_status, {:ok, :in_progress})
      assert {:snooze, 60} = MatchQuoteStatementsPollingWorker.perform(job)

      put_env_restore(:quote_statement_matcher_test_status, {:error, :polling_failed})

      log =
        capture_log(fn ->
          assert {:cancel, :polling_failed} = MatchQuoteStatementsPollingWorker.perform(job)
        end)

      assert log =~ "Statement matching job"
    end

    test "enqueues relevance verification when linking an already verified quote" do
      system_user = set_system_user()
      quote = sourced_quote()
      statement = statement_fixture(%{title: "Frontier AI labs should publish safety cases"})

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: quote.id,
          user_id: system_user.id,
          status: :ai_verified,
          comment: "Authentic",
          model: "test"
        })

      use_static_matcher([
        %{"statement_id" => statement.id, "answer" => "for", "comment" => "supports it"}
      ])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 MatchQuoteStatementsWorker.perform(%Oban.Job{
                   args: %{"opinion_id" => quote.id}
                 })

        assert [polling_job] = all_enqueued(worker: MatchQuoteStatementsPollingWorker)
        assert :ok = MatchQuoteStatementsPollingWorker.perform(polling_job)

        opinion_statement = OpinionsStatements.get_opinion_statement(quote.id, statement.id)

        assert_enqueued(
          worker: VerificationWorker,
          args: %{"subject" => "relevance", "id" => opinion_statement.id}
        )
      end)
    end
  end
end
