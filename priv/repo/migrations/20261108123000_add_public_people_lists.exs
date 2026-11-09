defmodule YouCongress.Repo.Migrations.AddPublicPeopleLists do
  use Ecto.Migration

  def up do
    create table(:people_lists) do
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :version, :integer, null: false, default: 1
      timestamps()
    end

    create index(:people_lists, [:author_id])

    create table(:people_list_members) do
      add :people_list_id, references(:people_lists, on_delete: :delete_all), null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :reason, :text
      add :position, :integer, null: false, default: 0
      timestamps()
    end

    create unique_index(:people_list_members, [:people_list_id, :author_id])

    # Preserve already-public picks as ordinary named lists. No persistent link
    # connects a public list to a private Council.
    execute """
    INSERT INTO people_lists (author_id, name, inserted_at, updated_at)
    SELECT c.author_id, LEFT(COALESCE(a.name, 'My') || ' picks', 120), NOW(), NOW()
    FROM councils c JOIN authors a ON a.id = c.author_id WHERE c.published
    """

    execute """
    INSERT INTO people_list_members (people_list_id, author_id, reason, position, inserted_at, updated_at)
    SELECT p.id, m.author_id, m.reason,
           ROW_NUMBER() OVER (PARTITION BY p.id ORDER BY m.id) - 1, NOW(), NOW()
    FROM people_lists p JOIN councils c ON c.author_id = p.author_id AND c.published
    JOIN council_lists l ON l.council_id = c.id
    JOIN council_members m ON m.list_id = l.id
    """

    execute "UPDATE councils SET published = false"
  end

  def down do
    drop table(:people_list_members)
    drop table(:people_lists)
  end
end
