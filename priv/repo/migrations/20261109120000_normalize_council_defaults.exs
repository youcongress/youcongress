defmodule YouCongress.Repo.Migrations.NormalizeCouncilDefaults do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO halls (name, inserted_at, updated_at)
    SELECT 'impact-on-labor', NOW(), NOW()
    WHERE NOT EXISTS (SELECT 1 FROM halls WHERE name = 'impact-on-labor')
    """

    # This is a one-time cleanup of the original defaults. Keep the Environment
    # hall and all people lists: only their Council assignments are removed.
    execute """
    DO $$
    DECLARE council RECORD; changed INTEGER; affected INTEGER; labor_id BIGINT;
    BEGIN
      SELECT MIN(id) INTO labor_id FROM halls WHERE name = 'impact-on-labor';
      FOR council IN SELECT id, author_id FROM councils ORDER BY id FOR UPDATE LOOP
        changed := 0;

        DELETE FROM council_lists l USING halls h
        WHERE l.council_id = council.id AND l.hall_id = h.id AND h.name = 'environment';
        GET DIAGNOSTICS affected = ROW_COUNT;
        changed := changed + affected;

        -- Rename only owned, private lists with the old default names. Public,
        -- followed and custom-named lists retain their names and URLs.
        UPDATE people_lists p
        SET name = CASE WHEN l.fallback THEN 'All statements' ELSE 'Impact on labor' END,
            version = p.version + 1, updated_at = NOW()
        FROM council_lists l LEFT JOIN halls h ON h.id = l.hall_id
        WHERE l.council_id = council.id AND l.people_list_id = p.id
          AND p.author_id = council.author_id AND NOT p.public
          AND ((l.fallback AND p.name IN ('General', 'Council'))
            OR (h.name = 'impact-on-jobs' AND p.name = 'Impact on jobs'));
        GET DIAGNOSTICS affected = ROW_COUNT;
        changed := changed + affected;

        UPDATE council_lists l SET hall_id = labor_id, updated_at = NOW()
        FROM halls h
        WHERE l.council_id = council.id AND l.hall_id = h.id AND h.name = 'impact-on-jobs';
        GET DIAGNOSTICS affected = ROW_COUNT;
        changed := changed + affected;

        IF changed > 0 THEN
          WITH ordered AS (
            SELECT id, ROW_NUMBER() OVER (ORDER BY fallback, position, id) - 1 AS position
            FROM council_lists WHERE council_id = council.id
          )
          UPDATE council_lists l SET position = ordered.position, updated_at = NOW()
          FROM ordered WHERE l.id = ordered.id AND l.position <> ordered.position;

          UPDATE councils SET version = version + 1, updated_at = NOW() WHERE id = council.id;
          UPDATE council_decisions SET council_version = -1 WHERE author_id = council.author_id;

          INSERT INTO oban_jobs (state, queue, worker, args, max_attempts, inserted_at, scheduled_at)
          VALUES ('available', 'default', 'YouCongress.Workers.RefreshCouncilWorker',
            jsonb_build_object('author_id', council.author_id), 20, NOW(), NOW());
        END IF;
      END LOOP;
    END $$
    """
  end

  def down do
    raise "Removed Council assignments require a data-preserving migration to restore."
  end
end
