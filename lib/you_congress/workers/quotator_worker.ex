defmodule YouCongress.Workers.QuotatorWorker do
  @moduledoc """
  Prepares sourced quote generation for a voting: calls QuotatorAI, updates
  generating counts, and enqueues per-quote jobs.
  """

  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.Votings
  alias YouCongress.Opinions.Quotes.QuotatorAI
  alias YouCongress.Opinions.Quotes.Quotator

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, binary} | :error
  def perform(%Oban.Job{attempt: attempt}) when attempt == @max_attempts do
    Logger.info("Failed to prepare sourced quotes. Max attempts reached.")
    {:cancel, "Max attempts reached."}
  end

  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id, preload: [:votes, :authors])

    exclude_existent_names =
      voting.votes
      |> Enum.map(& &1.author)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.name)

    Quotator.find_and_save_quotes(voting.title, exclude_existent_names) do
  end
end
