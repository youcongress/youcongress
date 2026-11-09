defmodule YouCongress.Repo.Migrations.RefreshCouncilParticipatingMajorities do
  use Ecto.Migration

  def up do
    # Recompute saved decisions using For/Against only, preserving direct votes.
    execute """
    INSERT INTO oban_jobs (state, queue, worker, args, max_attempts, inserted_at, scheduled_at)
    SELECT 'available', 'default', 'YouCongress.Workers.RefreshCouncilWorker',
           jsonb_build_object('author_id', author_id), 20, NOW(), NOW() FROM councils
    """
  end

  def down, do: :ok
end
