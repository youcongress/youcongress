defmodule YouCongress.Workers.StatementSynthesisPollingWorkerTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Statements
  alias YouCongress.Statements.Synthesis
  alias YouCongress.Workers.StatementSynthesisPollingWorker

  defmodule MalformedSynthesis do
    @behaviour YouCongress.Statements.Synthesis

    def submit(_statement, _votes), do: {:ok, "malformed"}
    # The decode-failure shape VerifierAI-style plumbing produces on bad JSON.
    def check_job_status(_job_id), do: {:ok, :completed, %{"model" => "fake-llm"}}
  end

  defmodule InProgressSynthesis do
    @behaviour YouCongress.Statements.Synthesis

    def submit(_statement, _votes), do: {:ok, "in-progress"}
    def check_job_status(_job_id), do: {:ok, :in_progress}
  end

  defmodule FailingSynthesis do
    @behaviour YouCongress.Statements.Synthesis

    def submit(_statement, _votes), do: {:ok, "failing"}
    def check_job_status(_job_id), do: {:error, :boom}
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
    StatementSynthesisPollingWorker.perform(%Oban.Job{args: args})
  end

  describe "perform/1" do
    test "persists the sanitized synthesis when the job completes" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 3)

      assert :ok =
               perform(%{
                 "job_id" => "fake:synthesis:#{statement.id}",
                 "statement_id" => statement.id,
                 "quotes_count" => 25
               })

      statement = Statements.get_statement!(statement.id)
      assert statement.synthesis["headline"] =~ "Fake synthesis"
      assert statement.synthesis["model"] == "fake-llm"
      assert statement.synthesis_quotes_count == 25
      assert %DateTime{} = statement.synthesis_generated_at

      # Every cited id is one of the statement's current quotes.
      cited = Synthesis.cited_opinion_ids(statement.synthesis)
      assert cited != []
      assert MapSet.subset?(MapSet.new(cited), Synthesis.valid_quote_ids(statement.id))
    end

    test "cancels and keeps the previous synthesis on a malformed payload" do
      put_env_restore(:quote_synthesis_implementation, MalformedSynthesis)
      statement = statement_fixture()

      {:ok, statement} =
        Statements.update_synthesis(statement, %{
          synthesis: %{"headline" => "old", "conclusion" => "old"},
          synthesis_quotes_count: 30
        })

      assert {:cancel, :invalid_synthesis} =
               perform(%{
                 "job_id" => "malformed",
                 "statement_id" => statement.id,
                 "quotes_count" => 40
               })

      statement = Statements.get_statement!(statement.id)
      assert statement.synthesis["headline"] == "old"
      assert statement.synthesis_quotes_count == 30
    end

    test "snoozes while the job is in progress" do
      put_env_restore(:quote_synthesis_implementation, InProgressSynthesis)
      statement = statement_fixture()

      assert {:snooze, 60} =
               perform(%{"job_id" => "in-progress", "statement_id" => statement.id})
    end

    test "cancels when the job failed" do
      put_env_restore(:quote_synthesis_implementation, FailingSynthesis)
      statement = statement_fixture()

      assert {:cancel, :boom} =
               perform(%{"job_id" => "failing", "statement_id" => statement.id})
    end

    test "no-ops when the statement was deleted mid-flight" do
      assert :ok =
               perform(%{
                 "job_id" => "fake:synthesis:-1",
                 "statement_id" => -1,
                 "quotes_count" => 25
               })
    end
  end
end
