defmodule YouCongress.Workers.VerificationPollingWorker do
  @moduledoc """
  Polls the LLM for the result of a verification job and, once complete, records
  the verification and cascades to the next pipeline stage.

  Retries every minute for up to 90 minutes, mirroring the QuotatorPollingWorker.
  """

  use Oban.Worker, queue: :verification, max_attempts: 90

  require Logger

  alias YouCongress.Verifications.Verifier
  alias YouCongress.Verifications.AIVerifications

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"subject" => subject, "id" => id, "job_id" => job_id} = args
      }) do
    case Verifier.check_job_status(job_id) do
      {:ok, :completed, result} ->
        AIVerifications.record_and_cascade(
          subject,
          id,
          result,
          Map.take(args, ["opinion_id", "correction_attempts"])
        )

        :ok

      {:ok, :in_progress} ->
        {:snooze, 60}

      {:error, reason} ->
        Logger.error("Verification job #{job_id} (#{subject} ##{id}) failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end
end
