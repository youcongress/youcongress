defmodule YouCongress.Workers.QuotatorPollingWorker do
  @moduledoc """
  Polls OpenAI for the status of a quote generation job.
  Retries every minute for up to 90 minutes.
  """
  use Oban.Worker, max_attempts: 90

  require Logger
  alias YouCongress.Opinions.Quotes.{Quotator, QuotatorAI}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"job_id" => job_id, "voting_id" => voting_id, "user_id" => user_id}
      }) do
    Logger.info("Polling OpenAI job #{job_id} for voting #{voting_id}...")

    case QuotatorAI.check_job_status(job_id) do
      {:ok, :completed, %{quotes: quotes}} ->
        Logger.info("Job #{job_id} completed. Saving quotes...")

        Quotator.save_quotes_from_job(%{
          voting_id: voting_id,
          quotes: quotes,
          user_id: user_id
        })

        :ok

      {:ok, :in_progress} ->
        Logger.info("Job #{job_id} still in progress. Snoozing...")
        {:snooze, 60}

      {:error, reason} ->
        Logger.error("Job #{job_id} failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  @impl Oban.Worker
  def backoff(_job), do: 60
end
