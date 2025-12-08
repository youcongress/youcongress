defmodule YouCongress.Repo.Migrations.AddSearchTrigramIndexes do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    create index(:votings, [:title],
             name: :votings_title_trgm_index,
             using: :gin,
             opclass: :gin_trgm_ops
           )

    create index(:authors, [:name],
             name: :authors_name_trgm_index,
             using: :gin,
             opclass: :gin_trgm_ops
           )

    create index(:authors, [:twitter_username],
             name: :authors_twitter_username_trgm_index,
             using: :gin,
             opclass: :gin_trgm_ops
           )

    create index(:halls, [:name],
             name: :halls_name_trgm_index,
             using: :gin,
             opclass: :gin_trgm_ops
           )

    create index(:opinions, [:content],
             name: :opinions_content_trgm_index,
             using: :gin,
             opclass: :gin_trgm_ops
           )
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
