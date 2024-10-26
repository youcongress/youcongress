defmodule YouCongress.Workers.VotingHallsGeneratorWorker do
  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  alias YouCongress.HallsVotings

  def perform(%Oban.Job{args: %{"voting_id" => voting_id}}) do
    HallsVotings.sync!(voting_id)
  end
end
