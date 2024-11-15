defmodule YouCongress.Workers.Votings.SyncAllVotingsLikesCountWorker do
  @moduledoc """
  Sync all votings opinion likes count
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Votings
  alias YouCongress.Workers.Votings.SyncVotingLikesCountWorker

  def perform(%Oban.Job{}) do
    for voting <- Votings.list_votings() do
      %{voting_id: voting.id}
      |> SyncVotingLikesCountWorker.new()
      |> Oban.insert()
    end

    :ok
  end
end
