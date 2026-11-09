defmodule YouCongress.Workers.RefreshCouncilWorker do
  @moduledoc "Resumable Council refresh after list, migration, or identity changes."
  use Oban.Worker, unique: [period: 60, states: [:available, :scheduled]]
  @impl true
  def perform(%Oban.Job{args: %{"author_id" => id}}) do
    YouCongress.Councils.sync_legacy(id)
    YouCongress.DelegationVotes.update_author_delegated_votes(id)
  end
end
