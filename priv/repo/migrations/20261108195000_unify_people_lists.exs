defmodule YouCongress.Repo.Migrations.UnifyPeopleLists do
  use Ecto.Migration

  def up do
    alter table(:people_lists) do
      add :public, :boolean, null: false, default: false
    end

    alter table(:people_list_members) do
      add :source_url, :text
    end

    alter table(:council_lists) do
      add :people_list_id, references(:people_lists, on_delete: :nilify_all)
    end

    create index(:council_lists, [:people_list_id])
    execute "UPDATE people_lists SET public = true"
    flush()

    # Preserve private comments in a private copy when the existing public list differs.
    execute """
    DO $$
    DECLARE entry RECORD; shared BIGINT; copied BIGINT; candidate TEXT; suffix INTEGER;
    BEGIN
      FOR entry IN SELECT l.*, c.author_id FROM council_lists l JOIN councils c ON c.id=l.council_id LOOP
        SELECT people_list_id INTO shared FROM council_public_list_links WHERE council_list_id=entry.id;
        copied := NULL;
        IF shared IS NULL OR EXISTS (
          SELECT 1 FROM council_members m LEFT JOIN people_list_members p
            ON p.people_list_id=shared AND p.author_id=m.author_id
          WHERE m.list_id=entry.id AND (p.id IS NULL OR
            (NULLIF(m.reason, '') IS NOT NULL AND m.reason IS DISTINCT FROM p.reason) OR
            NULLIF(m.source_url, '') IS NOT NULL)
        ) THEN
          candidate := 'council-list-' || entry.id; suffix := 0;
          WHILE EXISTS(SELECT 1 FROM people_list_slugs WHERE author_id=entry.author_id AND slug=candidate) LOOP
            suffix := suffix + 1; candidate := 'council-list-' || entry.id || '-' || suffix;
          END LOOP;
          INSERT INTO people_lists(author_id,name,slug,version,public,inserted_at,updated_at)
          VALUES(entry.author_id, LEFT(entry.name || CASE WHEN shared IS NULL THEN '' ELSE ' (private notes)' END,120), candidate,1,false,entry.inserted_at,entry.updated_at)
          RETURNING id INTO copied;
          INSERT INTO people_list_slugs(author_id,people_list_id,slug) VALUES(entry.author_id,copied,candidate);
          INSERT INTO people_list_members(people_list_id,author_id,reason,source_url,position,inserted_at,updated_at)
          SELECT copied,author_id,reason,source_url,ROW_NUMBER() OVER(ORDER BY id)-1,inserted_at,updated_at
          FROM council_members WHERE list_id=entry.id;
        END IF;
        UPDATE council_lists SET people_list_id=COALESCE(shared,copied) WHERE id=entry.id;
      END LOOP;
    END $$
    """

    execute "ALTER TABLE reconsideration_delegate_selections DROP CONSTRAINT reconsideration_delegate_selections_council_member_id_fkey"

    execute """
    UPDATE reconsideration_delegate_selections s SET council_member_id = p.id
    FROM council_lists l JOIN people_list_members p ON p.people_list_id=l.people_list_id
    WHERE s.council_list_id=l.id AND s.delegate_author_id=p.author_id
    """

    execute """
    UPDATE reconsideration_delegate_selections s SET council_member_id = NULL
    WHERE NOT EXISTS (SELECT 1 FROM council_lists l JOIN people_list_members p ON p.people_list_id=l.people_list_id
      WHERE l.id=s.council_list_id AND p.id=s.council_member_id AND p.author_id=s.delegate_author_id)
    """

    execute "ALTER TABLE reconsideration_delegate_selections ADD CONSTRAINT reconsideration_delegate_selections_council_member_id_fkey FOREIGN KEY (council_member_id) REFERENCES people_list_members(id) ON DELETE SET NULL"

    drop table(:council_public_list_links)
    drop table(:council_members)

    alter table(:council_lists) do
      remove :name
    end

    execute """
    INSERT INTO oban_jobs(state,queue,worker,args,max_attempts,inserted_at,scheduled_at)
    SELECT 'available','default','YouCongress.Workers.RefreshCouncilWorker',jsonb_build_object('author_id',author_id),20,NOW(),NOW() FROM councils
    """
  end

  def down,
    do:
      raise(
        "Unified lists require a data-preserving migration to restore separate Council storage."
      )
end
