defmodule YouCongress.Workers.QuotatorWorker do
  @moduledoc """
  Uses AI to find sourced quotes for a poll.

  Args:
  - voting_id: the id of the voting
  - user_id: the id of the user who is generating the quotes
  """

  @max_attempts 1

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.Votings
  alias YouCongress.Opinions.Quotes.Quotator

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | :error
  def perform(%Oban.Job{args: %{"voting_id" => voting_id, "user_id" => user_id} = args}) do
    voting = Votings.get_voting!(voting_id, preload: [votes: [:author]])
    max_remaining_llm_calls = args["max_remaining_llm_calls"] || 6
    max_remaining_quotes = args["max_remaining_quotes"] || 50

    exclude_existent_names =
      voting.votes
      |> Enum.map(& &1.author)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)

    case Quotator.find_and_save_quotes(
           voting.id,
           exclude_existent_names,
           user_id,
           max_remaining_llm_calls,
           max_remaining_quotes
         ) do
      {:ok, :job_started} ->
        Logger.info("Finding quotes job started for voting #{voting.id}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to find and save quotes: #{inspect(reason)}")
        :error
    end
  end
end
