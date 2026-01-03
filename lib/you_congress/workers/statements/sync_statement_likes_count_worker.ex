defmodule YouCongress.Workers.Statements.SyncStatementLikesCountWorker do
  @moduledoc """
  Sync a statement opinion likes count
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Statements

  def perform(%Oban.Job{args: %{"statement_id" => statement_id}}) do
    statement = Statements.get_statement!(statement_id)

    Statements.sync_opinion_likes_count(statement)
  end
end
