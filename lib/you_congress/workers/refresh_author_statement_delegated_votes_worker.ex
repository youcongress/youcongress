defmodule YouCongress.Workers.RefreshAuthorStatementDelegatedVotesWorker do
  @moduledoc """
  Updates the delegated votes of an author for a statement.
  """

  use Oban.Worker

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"statement_id" => statement_id, "author_id" => author_id}}) do
    YouCongress.DelegationVotes.update_author_statement_delegated_votes(%{
      author_id: author_id,
      statement_id: statement_id
    })

    :ok
  end
end
