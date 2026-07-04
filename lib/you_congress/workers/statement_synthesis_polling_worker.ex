defmodule YouCongress.Workers.StatementSynthesisPollingWorker do
  @moduledoc """
  Polls OpenAI for the status of a statement synthesis job and persists the
  sanitized result. Retries every minute for up to 90 minutes.

  Cited opinion ids are validated against the statement's current quotes at
  persist time, so quotes deleted while the job ran never end up cited. A
  malformed payload cancels the job and leaves any previous synthesis intact.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 90,
    unique: [
      states: [:scheduled, :available, :executing, :retryable],
      keys: [:job_id]
    ]

  require Logger

  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.Synthesis

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id, "statement_id" => statement_id} = args}) do
    case Synthesis.check_job_status(job_id) do
      {:ok, :completed, raw} ->
        persist(statement_id, raw, args["quotes_count"])

      {:ok, :in_progress} ->
        {:snooze, 60}

      {:error, reason} ->
        Logger.error("Statement synthesis job #{job_id} failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp persist(statement_id, raw, quotes_count) do
    with %Statement{} = statement <- Statements.get_statement(statement_id),
         {:ok, synthesis} <- Synthesis.sanitize(raw, Synthesis.valid_quote_ids(statement_id)) do
      {:ok, _statement} =
        Statements.update_synthesis(statement, %{
          synthesis: synthesis,
          synthesis_generated_at: DateTime.truncate(DateTime.utc_now(), :second),
          synthesis_quotes_count: quotes_count || Synthesis.quotes_count(statement_id)
        })

      :ok
    else
      nil ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Discarding invalid synthesis for statement #{statement_id}: #{inspect(reason)}"
        )

        {:cancel, reason}
    end
  end
end
