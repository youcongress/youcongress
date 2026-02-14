defmodule YouCongress.Workers.QuotatorPollingWorker do
  @moduledoc """
  Polls OpenAI for the status of a quote generation job.
  Retries every minute for up to 90 minutes.
  """
  use Oban.Worker, queue: :default, max_attempts: 90

  require Logger
  alias YouCongress.Opinions.Quotes.{Quotator, QuotatorAI}
  alias YouCongress.Workers.QuotatorWorker
  alias YouCongress.Accounts
  alias YouCongress.Accounts.UserNotifier
  alias YouCongress.Statements

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "job_id" => job_id,
            "statement_id" => statement_id,
            "user_id" => user_id,
            "max_remaining_llm_calls" => max_remaining_llm_calls,
            "max_remaining_quotes" => max_remaining_quotes
          } = args
      }) do
    total_quotes_added = args["total_quotes_added"] || 0
    Logger.info("Polling OpenAI job #{job_id} for statement #{statement_id}...")

    case QuotatorAI.check_job_status(job_id) do
      {:ok, :completed, %{quotes: quotes}} ->
        Logger.info("Job #{job_id} completed. Saving quotes...")

        result =
          Quotator.save_quotes_from_job(%{
            statement_id: statement_id,
            quotes: quotes,
            user_id: user_id
          })

        maybe_call_llm_again(
          result,
          statement_id,
          user_id,
          max_remaining_llm_calls,
          max_remaining_quotes,
          total_quotes_added
        )

      {:ok, :in_progress} ->
        Logger.info("Job #{job_id} still in progress. Retrying in 1 minute...")
        {:snooze, 60}

      {:error, reason} ->
        Logger.error("Job #{job_id} failed: #{inspect(reason)}")
        send_completion_email(user_id, statement_id, total_quotes_added)
        {:cancel, reason}
    end
  end

  defp maybe_call_llm_again(
         {:ok, num_saved_quotes},
         statement_id,
         user_id,
         max_remaining_llm_calls,
         max_remaining_quotes,
         total_quotes_added
       ) do
    max_remaining_quotes = max_remaining_quotes - num_saved_quotes
    total_quotes_added = total_quotes_added + num_saved_quotes

    cond do
      num_saved_quotes == 0 ->
        Logger.debug(
          "No quotes saved. No more llm calls despite #{max_remaining_quotes} quotes left."
        )

        send_completion_email(user_id, statement_id, total_quotes_added)
        :ok

      max_remaining_quotes == 0 ->
        Logger.debug("No more quotes left.")
        send_completion_email(user_id, statement_id, total_quotes_added)
        :ok

      max_remaining_llm_calls <= 0 ->
        Logger.debug("No more llm calls left.")
        send_completion_email(user_id, statement_id, total_quotes_added)
        :ok

      true ->
        max_remaining_llm_calls = max_remaining_llm_calls - 1

        Logger.debug(
          "Calling llm again with #{max_remaining_llm_calls} calls left and #{max_remaining_quotes} quotes left."
        )

        %{
          statement_id: statement_id,
          user_id: user_id,
          max_remaining_quotes: max_remaining_quotes,
          max_remaining_llm_calls: max_remaining_llm_calls,
          total_quotes_added: total_quotes_added
        }
        |> QuotatorWorker.new()
        |> Oban.insert()
    end

    :ok
  end

  defp maybe_call_llm_again(_, _, _, _, _, _), do: :ok

  defp send_completion_email(user_id, statement_id, total_quotes_added) do
    user = Accounts.get_user!(user_id)
    statement = Statements.get_statement!(statement_id)

    UserNotifier.deliver_quotes_found_notification(
      user.email,
      statement.title,
      total_quotes_added
    )
  end
end
