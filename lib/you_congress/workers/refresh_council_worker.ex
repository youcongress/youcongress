defmodule YouCongress.Workers.RefreshCouncilWorker do
  @moduledoc "Resumable full-council refresh for migrations and identity changes."
  use Oban.Worker, unique: [period: 60, states: [:available, :scheduled]]
  @impl true
  def perform(%Oban.Job{args: %{"author_id" => id}}),
    do: YouCongress.DelegationVotes.update_author_delegated_votes(id)
end
