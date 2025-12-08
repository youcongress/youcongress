defmodule YouCongress.Repo.Migrations.AddSearchTrigramIndexes do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    execute("""
    CREATE INDEX IF NOT EXISTS votings_title_trgm_index
    ON votings USING GIN (title gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS authors_name_trgm_index
    ON authors USING GIN (name gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS authors_twitter_username_trgm_index
    ON authors USING GIN (twitter_username gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS halls_name_trgm_index
    ON halls USING GIN (name gin_trgm_ops)
    """)

    execute("""
    CREATE INDEX IF NOT EXISTS opinions_content_trgm_index
    ON opinions USING GIN (content gin_trgm_ops)
    """)
  end

  def down do
    drop_if_exists index(:opinions, [:content], name: :opinions_content_trgm_index)
    drop_if_exists index(:halls, [:name], name: :halls_name_trgm_index)

    drop_if_exists index(:authors, [:twitter_username],
                     name: :authors_twitter_username_trgm_index
                   )

    drop_if_exists index(:authors, [:name], name: :authors_name_trgm_index)
    drop_if_exists index(:votings, [:title], name: :votings_title_trgm_index)
  end
end
