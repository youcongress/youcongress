defmodule YouCongress.Workers.StatementSynthesisWorker do
  @moduledoc """
  Starts a background OpenAI job that synthesizes the sourced quotes of a
  statement, then hands off to `StatementSynthesisPollingWorker`.

  Eligibility is re-checked at perform time: bursts of quote additions enqueue
  many jobs (deduped by uniqueness) and conditions can change between enqueue
  and execution. A `"force" => true` job (admin regeneration, backfill)
  bypasses the staleness delta but not the feature flag or the quote floor.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      states: [:scheduled, :available, :executing, :retryable],
      keys: [:statement_id]
    ]

  require Logger

  alias YouCongress.FeatureFlags
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.Synthesis
  alias YouCongress.Votes
  alias YouCongress.Workers.StatementSynthesisPollingWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"statement_id" => statement_id} = args}) do
    with %Statement{} = statement <- Statements.get_statement(statement_id),
         false <- Synthesis.polling_in_progress?(statement_id),
         quotes_count = Synthesis.quotes_count(statement_id),
         true <- submit?(statement, quotes_count, args["force"] == true) do
      submit(statement, quotes_count)
    else
      _ -> :ok
    end
  end

  defp submit?(_statement, quotes_count, true) do
    FeatureFlags.enabled?(:quote_synthesis) and quotes_count >= Synthesis.min_quotes()
  end

  defp submit?(statement, quotes_count, false), do: Synthesis.eligible?(statement, quotes_count)

  defp submit(statement, quotes_count) do
    votes =
      Votes.list_votes_with_opinion(statement.id,
        include: [opinion: :author],
        source_filter: :quotes,
        twin_options: [false]
      )

    case Synthesis.submit(statement, votes) do
      {:ok, job_id} ->
        %{"job_id" => job_id, "statement_id" => statement.id, "quotes_count" => quotes_count}
        |> StatementSynthesisPollingWorker.new()
        |> Oban.insert()

        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to submit synthesis for statement #{statement.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
