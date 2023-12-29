defmodule YouCongress.Workers.RefreshAuthorVotingDelegatedVotesWorker do
  @moduledoc """
  Updates the delegated votes of an author for a voting.
  """

  use Oban.Worker

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"voting_id" => voting_id, "author_id" => author_id}}) do
    YouCongress.DelegationVotes.update_author_voting_delegated_votes(%{
      author_id: author_id,
      voting_id: voting_id
    })

    :ok
  end
end
