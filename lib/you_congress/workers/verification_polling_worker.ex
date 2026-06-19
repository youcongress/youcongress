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
  alias YouCongress.Workers.JobMetadata

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args: %{"subject" => subject, "id" => id, "job_id" => job_id} = args
        } = job
      ) do
    case Verifier.check_job_status(job_id) do
      {:ok, :completed, result} ->
        AIVerifications.record_and_cascade(
          subject,
          id,
          result,
          Map.take(args, ["opinion_id", "correction_attempts"])
        )

        store_metadata(job, args, %{
          "status" => "completed",
          "outcome" => verification_outcome(subject, result),
          "subject" => subject,
          "subject_id" => id,
          "verification_job_id" => job_id,
          "result" => result
        })

        :ok

      {:ok, :in_progress} ->
        store_metadata(job, args, %{
          "status" => "in_progress",
          "subject" => subject,
          "subject_id" => id,
          "verification_job_id" => job_id
        })

        {:snooze, 60}

      {:error, reason} ->
        store_metadata(job, args, %{
          "status" => "cancelled",
          "subject" => subject,
          "subject_id" => id,
          "verification_job_id" => job_id,
          "reason" => JobMetadata.format_reason(reason)
        })

        Logger.error("Verification job #{job_id} (#{subject} ##{id}) failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp store_metadata(job, args, metadata) do
    metadata =
      if is_integer(job.id), do: Map.put(metadata, "polling_job_id", job.id), else: metadata

    JobMetadata.put(job, "verification", metadata)

    case args["verification_worker_job_id"] do
      job_id when is_integer(job_id) -> JobMetadata.put(job_id, "verification", metadata)
      _job_id -> :ok
    end
  end

  defp verification_outcome("vote", %{"correct_answer" => answer})
       when answer in ~w(for against abstain),
       do: "ai_verified"

  defp verification_outcome("vote", _result), do: "ai_unverifiable"
  defp verification_outcome(_subject, %{"status" => status}), do: status
  defp verification_outcome(_subject, _result), do: "unknown"
end
