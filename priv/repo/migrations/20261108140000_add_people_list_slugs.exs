defmodule YouCongress.Repo.Migrations.AddPeopleListSlugs do
  use Ecto.Migration

  def up do
    alter table(:people_lists) do
      add :slug, :string
    end

    execute """
    UPDATE people_lists SET slug =
      COALESCE(NULLIF(TRIM(BOTH '-' FROM LEFT(REGEXP_REPLACE(LOWER(name), '[^a-z0-9]+', '-', 'g'), 60)), ''), 'list')
      || '-' || id::text
    """

    alter table(:people_lists) do
      modify :slug, :string, null: false
    end

    create unique_index(:people_lists, [:author_id, :slug])

    create table(:people_list_slugs) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :people_list_id, references(:people_lists, on_delete: :delete_all), null: false
      add :slug, :string, null: false
    end

    create unique_index(:people_list_slugs, [:author_id, :slug])
    create index(:people_list_slugs, [:people_list_id])

    execute """
    INSERT INTO people_list_slugs (author_id, people_list_id, slug)
    SELECT author_id, id, slug FROM people_lists
    """
  end

  def down do
    drop table(:people_list_slugs)
    drop unique_index(:people_lists, [:author_id, :slug])

    alter table(:people_lists) do
      remove :slug
    end
  end
end
