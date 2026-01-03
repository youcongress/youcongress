defmodule YouCongress.Workers.TouchStatementWorker do
  @moduledoc """
  Touch a statement
  """

  use Oban.Worker

  alias YouCongress.HallsStatements
  alias YouCongress.Statements

  def perform(%Oban.Job{}) do
    "ai"
    |> HallsStatements.get_random_statement()
    |> Statements.touch_statement()

    :ok
  end
end
