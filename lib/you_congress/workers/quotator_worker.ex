defmodule YouCongress.Workers.QuotatorWorker do
  @moduledoc """
  Uses AI to find sourced quotes for a poll.

  Args:
  - voting_id: the id of the voting
  - user_id: the id of the user who is generating the quotes
  - num_times: the number of times to generate n quotes
  """

  @max_attempts 1

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.Votings
  alias YouCongress.Opinions.Quotes.Quotator

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | :error
  def perform(%Oban.Job{
        args: %{"voting_id" => voting_id, "user_id" => user_id, "num_times" => _num_times} = args
      }) do
    voting = Votings.get_voting!(voting_id, preload: [votes: [:author]])

    exclude_existent_names =
      voting.votes
      |> Enum.map(& &1.author)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)

    case Quotator.find_and_save_quotes(voting.id, exclude_existent_names, user_id) do
      {:ok, saved_count} ->
        maybe_continue_batch(args, saved_count)
        :ok

      {:error, reason} ->
        Logger.error("Failed to find and save quotes: #{inspect(reason)}")
        :error
    end
  end

  defp maybe_continue_batch(
         %{"num_times" => num_times, "voting_id" => voting_id} = args,
         saved_count
       ) do
    if saved_count == Quotator.number_of_quotes() do
      if num_times > 0 do
        Logger.info(
          "Successfully generated #{saved_count} quotes for voting #{voting_id}. Continuing to generate more quotes. Batch #{num_times + 1}/#{@max_attempts}"
        )

        %{args | "num_times" => num_times - 1}
        |> __MODULE__.new()
        |> Oban.insert()
      else
        Logger.info(
          "Reached max batches for voting #{voting_id}. Successfully generated #{saved_count} quotes in final batch."
        )
      end
    else
      Logger.warning(
        "Quote generation unsuccessful for voting #{voting_id}. Only saved #{saved_count}/#{Quotator.number_of_quotes()} quotes. Stopping generation."
      )

      :ok
    end
  end
end
