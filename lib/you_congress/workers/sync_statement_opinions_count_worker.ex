defmodule YouCongress.Workers.SyncStatementOpinionsCountWorker do
  @moduledoc """
  Syncs the opinions_count of a statement.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Statements

  @impl true
  def perform(%Oban.Job{args: %{"statement_id" => statement_id}}) do
    case Statements.get_statement(statement_id) do
      nil -> :ok
      statement -> Statements.sync_opinions_count(statement)
    end
  end
end
