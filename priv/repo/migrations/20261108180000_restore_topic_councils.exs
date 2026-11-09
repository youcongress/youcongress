defmodule YouCongress.Repo.Migrations.RestoreTopicCouncils do
  use Ecto.Migration

  def up do
    drop index(:council_lists, [:council_id], name: :one_list_per_council)

    execute """
    INSERT INTO halls (name, inserted_at, updated_at)
    SELECT name, NOW(), NOW() FROM (VALUES ('ai-governance'), ('impact-on-jobs'), ('environment')) AS defaults(name)
    WHERE NOT EXISTS (SELECT 1 FROM halls h WHERE h.name = defaults.name)
    """

    execute "UPDATE council_lists SET name = 'General', position = 3 WHERE fallback"

    execute """
    INSERT INTO council_lists (council_id, hall_id, name, position, fallback, inserted_at, updated_at)
    SELECT c.id, h.id, defaults.label, defaults.position, false, NOW(), NOW()
    FROM councils c
    CROSS JOIN (VALUES ('ai-governance', 'AI governance', 0), ('impact-on-jobs', 'Impact on jobs', 1), ('environment', 'Environment', 2)) AS defaults(hall, label, position)
    JOIN halls h ON h.name = defaults.hall
    """

    alter table(:council_public_list_links) do
      add :council_list_id, references(:council_lists, on_delete: :delete_all)
    end

    execute """
    UPDATE council_public_list_links link SET council_list_id = l.id
    FROM councils c JOIN council_lists l ON l.council_id = c.id AND l.fallback
    WHERE c.author_id = link.author_id
    """

    execute "ALTER TABLE council_public_list_links DROP CONSTRAINT council_public_list_links_pkey"
    execute "ALTER TABLE council_public_list_links ALTER COLUMN council_list_id SET NOT NULL"
    execute "ALTER TABLE council_public_list_links ADD PRIMARY KEY (council_list_id)"

    # Preserve existing projections; refresh them through the normal resumable worker.
    execute """
    INSERT INTO oban_jobs (state, queue, worker, args, max_attempts, inserted_at, scheduled_at)
    SELECT 'available', 'default', 'YouCongress.Workers.RefreshCouncilWorker',
           jsonb_build_object('author_id', author_id), 20, NOW(), NOW() FROM councils
    """
  end

  def down do
    raise "Topic Councils require a data-preserving migration to return to single-list Councils."
  end
end
