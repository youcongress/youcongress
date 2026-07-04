defmodule YouCongress.Workers.StatementSynthesisWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Statements
  alias YouCongress.Statements.Synthesis
  alias YouCongress.Workers.StatementSynthesisPollingWorker
  alias YouCongress.Workers.StatementSynthesisWorker

  defmodule FailingSynthesis do
    @behaviour YouCongress.Statements.Synthesis

    def submit(_statement, _votes), do: {:error, :submission_failed}
    def check_job_status(_job_id), do: {:error, :polling_failed}
  end

  defp enable_synthesis_flag do
    put_env_restore(:feature_flags, %{quote_synthesis: true})
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

  defp perform(args) do
    StatementSynthesisWorker.perform(%Oban.Job{args: args})
  end

  describe "perform/1" do
    test "submits and enqueues the polling worker when eligible" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)
      fake_job_id = "fake:synthesis:#{statement.id}"

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform(%{"statement_id" => statement.id})

        assert [job] = all_enqueued(worker: StatementSynthesisPollingWorker)

        assert %{
                 "job_id" => ^fake_job_id,
                 "statement_id" => _,
                 "quotes_count" => 25
               } = job.args
      end)
    end

    test "skips below the quote floor" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 24)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform(%{"statement_id" => statement.id})
        assert [] = all_enqueued(worker: StatementSynthesisPollingWorker)
      end)
    end

    test "skips when the feature flag is disabled" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform(%{"statement_id" => statement.id})
        assert [] = all_enqueued(worker: StatementSynthesisPollingWorker)
      end)
    end

    test "skips when the statement no longer exists" do
      enable_synthesis_flag()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform(%{"statement_id" => -1})
        assert [] = all_enqueued(worker: StatementSynthesisPollingWorker)
      end)
    end

    test "skips while a polling job is already active" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _job} =
          %{"job_id" => "other-job", "statement_id" => statement.id, "quotes_count" => 25}
          |> StatementSynthesisPollingWorker.new()
          |> Oban.insert()

        assert Synthesis.in_progress?(statement.id)
        assert :ok = perform(%{"statement_id" => statement.id})

        assert [%{args: %{"job_id" => "other-job"}}] =
                 all_enqueued(worker: StatementSynthesisPollingWorker)
      end)
    end

    test "force bypasses the staleness delta but not the quote floor" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      {:ok, _} =
        Statements.update_synthesis(statement, %{
          synthesis: %{"headline" => "H", "conclusion" => "C"},
          synthesis_quotes_count: 25
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        # Delta is 0, so a regular run skips...
        assert :ok = perform(%{"statement_id" => statement.id})
        assert [] = all_enqueued(worker: StatementSynthesisPollingWorker)

        # ...while a forced run submits.
        assert :ok = perform(%{"statement_id" => statement.id, "force" => true})
        assert [_job] = all_enqueued(worker: StatementSynthesisPollingWorker)
      end)

      small = statement_fixture(%{title: "small statement"})
      fill_statement_with_quotes(small.id, 24)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = perform(%{"statement_id" => small.id, "force" => true})

        refute Enum.any?(
                 all_enqueued(worker: StatementSynthesisPollingWorker),
                 &(&1.args["statement_id"] == small.id)
               )
      end)
    end

    test "returns an error when submission fails so Oban can retry" do
      enable_synthesis_flag()
      put_env_restore(:quote_synthesis_implementation, FailingSynthesis)
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:error, :submission_failed} = perform(%{"statement_id" => statement.id})
        assert [] = all_enqueued(worker: StatementSynthesisPollingWorker)
      end)
    end
  end

  describe "integration with the opinions-count sync trigger" do
    test "the sync worker triggers generation through the whole pipeline" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      assert {:ok, _statement} =
               YouCongress.Workers.SyncStatementOpinionsCountWorker.perform(%Oban.Job{
                 args: %{"statement_id" => statement.id}
               })

      statement = Statements.get_statement!(statement.id)
      assert statement.synthesis["headline"] =~ "Fake synthesis"
      assert statement.synthesis_quotes_count == 25
    end
  end
end
