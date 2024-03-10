defmodule YouCongress.Workers.OpinatorWorker do
  @moduledoc """
  Generates opinions and votes for a voting.
  """

  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  require Logger

  alias YouCongress.DigitalTwins
  alias YouCongress.Delegations
  alias YouCongress.DelegationVotes
  alias YouCongress.OpinatorWorker.GeneratingLeftServer

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok

  def perform(%Oban.Job{attempt: attempt, args: %{"voting_id" => voting_id}})
      when attempt == @max_attempts do
    Logger.info("Failed to generate vote. Max attempts reached.")
    GeneratingLeftServer.decrease_generating_left(voting_id)

    {:cancel, "Max attempts reached."}
  end

  def perform(%Oban.Job{args: %{"voting_id" => voting_id, "name" => name, "response" => response}}) do
    case DigitalTwins.generate_vote(voting_id, name, response) do
      {:ok, vote} ->
        refresh_delegated_votes(vote, voting_id)
        GeneratingLeftServer.decrease_generating_left(voting_id)

      {:error, error} ->
        Logger.error("Failed to generate vote. Retry. error: #{inspect(error)}")
        :error
    end
  end

  defp refresh_delegated_votes(vote, voting_id) do
    delegate_id = vote.author_id
    deleguee_ids = Delegations.deleguee_ids_by_delegate_id(delegate_id)

    for deleguee_id <- deleguee_ids do
      DelegationVotes.update_author_voting_delegated_votes(%{
        author_id: deleguee_id,
        voting_id: voting_id
      })
    end
  end
end
