defmodule YouCongress.Workers.VotingGeneratorWorker do
  @moduledoc """
  Generate a voting
  """

  use Oban.Worker

  def perform(%Oban.Job{}) do
    YouCongress.Votings.Generator.generate()
  end
end
