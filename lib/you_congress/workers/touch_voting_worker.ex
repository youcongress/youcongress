defmodule YouCongress.Workers.TouchVotingWorker do
  @moduledoc """
  Touch a voting
  """

  use Oban.Worker

  alias YouCongress.HallsVotings
  alias YouCongress.Votings

  def perform(%Oban.Job{}) do
    "ai"
    |> HallsVotings.get_random_voting()
    |> Votings.touch_voting()

    :ok
  end
end
