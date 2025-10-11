defmodule YouCongress.Workers.QuotatorWorker do
  @moduledoc """
  Prepares sourced quote generation for a voting and triggers saving them.
  """

  @max_attempts 1

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.Votings
  alias YouCongress.Opinions.Quotes.Quotator

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | :error
  def perform(%Oban.Job{args: %{"voting_id" => voting_id, "user_id" => user_id}}) do
    voting = Votings.get_voting!(voting_id, preload: [votes: [:author]])

    exclude_existent_names =
      voting.votes
      |> Enum.map(& &1.author)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)

    case Quotator.find_and_save_quotes(voting.id, exclude_existent_names, user_id) do
      {:ok, _saved_count} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to find and save quotes: #{inspect(reason)}")
        :error
    end
  end
end
