defmodule YouCongress.Repo.Migrations.CreateOpinionsVotingsTable do
  use Ecto.Migration

  def change do
    create table(:opinions_votings, primary_key: false) do
      add :opinion_id, references(:opinions, on_delete: :delete_all), null: false
      add :voting_id, references(:votings, on_delete: :delete_all), null: false
    end

    create unique_index(:opinions_votings, [:opinion_id, :voting_id])
    create index(:opinions_votings, [:voting_id])

    # Migrate existing data from opinions.voting_id to the junction table
    execute """
            INSERT INTO opinions_votings (opinion_id, voting_id)
            SELECT id, voting_id
            FROM opinions
            WHERE voting_id IS NOT NULL
            """,
            ""

    # Remove the voting_id column from opinions table
    alter table(:opinions) do
      remove :voting_id
    end
  end
end
