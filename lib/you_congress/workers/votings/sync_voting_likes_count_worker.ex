defmodule YouCongress.Workers.Votings.SyncVotingLikesCountWorker do
  @moduledoc """
  Sync a voting opinion likes count
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Votings

  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    voting = Votings.get_voting!(voting_id)

    Votings.sync_opinion_likes_count(voting)
  end
end
