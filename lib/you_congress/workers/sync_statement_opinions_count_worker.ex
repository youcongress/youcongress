defmodule YouCongress.Workers.SyncStatementOpinionsCountWorker do
  @moduledoc """
  Syncs the opinions_count of a statement.

  Since this runs on every quote add/remove, it is also the trigger point for
  the AI quote synthesis: after syncing, it enqueues a synthesis job when the
  statement has become eligible (enough quotes, no or stale synthesis).
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Statements
  alias YouCongress.Statements.Synthesis

  @impl true
  def perform(%Oban.Job{args: %{"statement_id" => statement_id}}) do
    case Statements.get_statement(statement_id) do
      nil ->
        :ok

      statement ->
        with {:ok, statement} <- Statements.sync_opinions_count(statement) do
          Synthesis.maybe_enqueue(statement)
          {:ok, statement}
        end
    end
  end
end
