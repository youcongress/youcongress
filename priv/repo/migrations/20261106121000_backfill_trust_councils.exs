defmodule YouCongress.Repo.Migrations.BackfillTrustCouncils do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO halls (name, inserted_at, updated_at)
    SELECT name, NOW(), NOW() FROM (VALUES ('ai-governance'), ('impact-on-labor'), ('ai-safety')) AS names(name)
    WHERE NOT EXISTS (SELECT 1 FROM halls h WHERE h.name = names.name)
    """

    execute """
    INSERT INTO councils (author_id, inserted_at, updated_at)
    SELECT DISTINCT deleguee_id, NOW(), NOW() FROM delegations
    ON CONFLICT (author_id) DO NOTHING
    """

    execute """
    INSERT INTO council_lists (council_id, hall_id, name, position, fallback, inserted_at, updated_at)
    SELECT c.id, (SELECT MIN(id) FROM halls WHERE name = defaults.hall), defaults.name,
           defaults.position, defaults.fallback, NOW(), NOW()
    FROM councils c CROSS JOIN (VALUES
      ('ai-governance', 'AI governance', 0, false),
      ('impact-on-labor', 'Impact on Jobs', 1, false),
      (NULL, 'General', 2, true)
    ) AS defaults(hall, name, position, fallback)
    WHERE NOT EXISTS (SELECT 1 FROM council_lists l WHERE l.council_id = c.id)
    """

    execute """
    INSERT INTO council_members (list_id, author_id, inserted_at, updated_at)
    SELECT l.id, d.delegate_id, NOW(), NOW()
    FROM delegations d JOIN councils c ON c.author_id = d.deleguee_id
    JOIN council_lists l ON l.council_id = c.id AND l.fallback
    WHERE d.deleguee_id <> d.delegate_id
    ON CONFLICT (list_id, author_id) DO NOTHING
    """

    execute """
    UPDATE votes v SET origin = CASE
      WHEN NOT v.direct THEN 'delegated'
      WHEN EXISTS (SELECT 1 FROM vote_verifications vv JOIN users u ON u.id = vv.user_id
                   WHERE vv.vote_id = v.id AND vv.status = 'endorsed' AND u.author_id = v.author_id)
        THEN 'self_cast'
      WHEN EXISTS (SELECT 1 FROM opinions o WHERE o.id = v.opinion_id
                   AND (NULLIF(BTRIM(o.source_url), '') IS NOT NULL OR NULLIF(BTRIM(o.source_text), '') IS NOT NULL))
        THEN 'inferred'
      ELSE 'legacy' END
    WHERE v.origin = 'legacy'
    """

    # Preserve every existing vote. Workers transactionally replace each projection
    # only after successfully evaluating and storing the new council decision.
    execute """
    INSERT INTO oban_jobs (queue, worker, args, state, scheduled_at, inserted_at)
    SELECT 'default', 'YouCongress.Workers.RefreshCouncilWorker',
           jsonb_build_object('author_id', author_id), 'available', NOW(), NOW()
    FROM councils
    """
  end

  def down, do: :ok
end
