defmodule YouCongress.Repo.Migrations.CreateOpinionsVotingsWithUserId do
  use Ecto.Migration

  def change do
    create table(:opinions_votings) do
      add :opinion_id, references(:opinions, on_delete: :delete_all), null: false
      add :voting_id, references(:votings, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all)

      timestamps()
    end

    create unique_index(:opinions_votings, [:opinion_id, :voting_id])
    create index(:opinions_votings, [:voting_id])
    create index(:opinions_votings, [:user_id])

    # Migrate existing data from opinions.voting_id to the junction table
    execute """
            INSERT INTO opinions_votings (opinion_id, voting_id, user_id, inserted_at, updated_at)
            SELECT
              o.id,
              o.voting_id,
              o.user_id,
              NOW(),
              NOW()
            FROM opinions o
            LEFT JOIN authors a ON o.author_id = a.id
            LEFT JOIN users u ON a.id = u.author_id
            WHERE o.voting_id IS NOT NULL
            """,
            ""

    # Remove the voting_id column from opinions table
    alter table(:opinions) do
      remove :voting_id
    end
  end
end
