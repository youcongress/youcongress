defmodule YouCongress.Workers.StatementHallsGeneratorWorker do
  @moduledoc """
  Oban worker for generating and syncing statement halls data.
  """

  @max_attempts 2

  use Oban.Worker, max_attempts: @max_attempts

  alias YouCongress.HallsStatements

  def perform(%Oban.Job{args: %{"statement_id" => statement_id}}) do
    HallsStatements.sync!(statement_id)
  end
end
