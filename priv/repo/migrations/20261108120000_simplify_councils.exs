defmodule YouCongress.Repo.Migrations.SimplifyCouncils do
  use Ecto.Migration

  def up do
    # Copy selections before removing topic lists; retain existing nonempty reasons.
    execute """
    INSERT INTO council_members (list_id, author_id, reason, source_url, inserted_at, updated_at)
    SELECT DISTINCT ON (target.id, m.author_id)
      target.id, m.author_id, m.reason, m.source_url, m.inserted_at, NOW()
    FROM council_lists source
    JOIN council_lists target ON target.council_id = source.council_id AND target.fallback
    JOIN council_members m ON m.list_id = source.id
    ORDER BY target.id, m.author_id, (NULLIF(BTRIM(m.reason), '') IS NOT NULL) DESC,
             source.fallback DESC, source.position, m.id
    ON CONFLICT (list_id, author_id) DO UPDATE SET
      reason = COALESCE(NULLIF(BTRIM(council_members.reason), ''), EXCLUDED.reason),
      source_url = COALESCE(NULLIF(council_members.source_url, ''), EXCLUDED.source_url),
      updated_at = NOW()
    """

    execute "DELETE FROM council_lists WHERE NOT fallback"
    execute "UPDATE council_lists SET name = 'Council', hall_id = NULL, position = 0"
    execute "UPDATE councils SET version = version + 1, updated_at = NOW()"
    create unique_index(:council_lists, [:council_id], name: :one_list_per_council)

    execute """
    INSERT INTO oban_jobs (queue, worker, args, state, scheduled_at, inserted_at)
    SELECT 'default', 'YouCongress.Workers.RefreshCouncilWorker',
           jsonb_build_object('author_id', author_id), 'available', NOW(), NOW()
    FROM councils
    """
  end

  def down do
    drop index(:council_lists, [:council_id], name: :one_list_per_council)
  end
end
