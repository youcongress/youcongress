defmodule YouCongress.Workers.QuotatorPollingWorker do
  @moduledoc """
  Polls OpenAI for the status of a quote generation job.
  Retries every minute for up to 90 minutes.
  """
  use Oban.Worker, queue: :default, max_attempts: 90

  require Logger
  alias YouCongress.Opinions.Quotes.{Quotator, QuotatorAI}
  alias YouCongress.Workers.QuotatorWorker

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "job_id" => job_id,
          "voting_id" => voting_id,
          "user_id" => user_id,
          "max_remaining_llm_calls" => max_remaining_llm_calls,
          "max_remaining_quotes" => max_remaining_quotes
        }
      }) do
    Logger.info("Polling OpenAI job #{job_id} for voting #{voting_id}...")

    case QuotatorAI.check_job_status(job_id) do
      {:ok, :completed, %{quotes: quotes}} ->
        Logger.info("Job #{job_id} completed. Saving quotes...")

        result =
          Quotator.save_quotes_from_job(%{
            voting_id: voting_id,
            quotes: quotes,
            user_id: user_id
          })

        maybe_call_llm_again(
          result,
          voting_id,
          user_id,
          max_remaining_llm_calls,
          max_remaining_quotes
        )

      {:ok, :in_progress} ->
        Logger.info("Job #{job_id} still in progress. Retrying in 1 minute...")
        {:snooze, 60}

      {:error, reason} ->
        Logger.error("Job #{job_id} failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp maybe_call_llm_again(
         {:ok, num_saved_quotes},
         voting_id,
         user_id,
         max_remaining_llm_calls,
         max_remaining_quotes
       ) do
    max_remaining_quotes = max_remaining_quotes - num_saved_quotes

    cond do
      num_saved_quotes == 0 ->
        Logger.debug(
          "No quotes saved. No more llm calls despite #{max_remaining_quotes} quotes left."
        )

        :ok

      max_remaining_quotes == 0 ->
        Logger.debug("No more quotes left.")
        :ok

      max_remaining_llm_calls <= 0 ->
        Logger.debug("No more llm calls left.")
        :ok

      true ->
        max_remaining_llm_calls = max_remaining_llm_calls - 1

        Logger.debug(
          "Calling llm again with #{max_remaining_llm_calls} calls left and #{max_remaining_quotes} quotes left."
        )

        %{
          voting_id: voting_id,
          user_id: user_id,
          max_remaining_quotes: max_remaining_quotes,
          max_remaining_llm_calls: max_remaining_llm_calls
        }
        |> QuotatorWorker.new()
        |> Oban.insert()
    end

    :ok
  end

  defp maybe_call_llm_again(_, _, _, _, _), do: :ok
end
