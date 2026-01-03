defmodule YouCongress.Workers.Statements.SyncAllStatementsLikesCountWorker do
  @moduledoc """
  Sync all statements opinion likes count
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Statements
  alias YouCongress.Workers.Statements.SyncStatementLikesCountWorker

  def perform(%Oban.Job{}) do
    for statement <- Statements.list_statements() do
      %{statement_id: statement.id}
      |> SyncStatementLikesCountWorker.new()
      |> Oban.insert()
    end

    :ok
  end
end
