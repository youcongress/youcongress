defmodule YouCongress.Repo.Migrations.RollbackOpinionsVotingsAndFix do
  use Ecto.Migration

  def up do
    # First, add the voting_id column back to opinions table temporarily
    alter table(:opinions) do
      add :voting_id, references(:votings, on_delete: :delete_all)
    end

    # Populate the voting_id from the junction table
    execute """
    UPDATE opinions
    SET voting_id = (
      SELECT voting_id
      FROM opinions_votings
      WHERE opinions_votings.opinion_id = opinions.id
      LIMIT 1
    )
    WHERE EXISTS (
      SELECT 1
      FROM opinions_votings
      WHERE opinions_votings.opinion_id = opinions.id
    )
    """

    # Drop the junction table
    drop table(:opinions_votings)

    # Recreate the junction table without timestamps
    create table(:opinions_votings, primary_key: false) do
      add :opinion_id, references(:opinions, on_delete: :delete_all), null: false
      add :voting_id, references(:votings, on_delete: :delete_all), null: false
    end

    create unique_index(:opinions_votings, [:opinion_id, :voting_id])
    create index(:opinions_votings, [:voting_id])

    # Migrate data back to the junction table (without timestamps)
    execute """
    INSERT INTO opinions_votings (opinion_id, voting_id)
    SELECT id, voting_id
    FROM opinions
    WHERE voting_id IS NOT NULL
    """

    # Remove the voting_id column from opinions table again
    alter table(:opinions) do
      remove :voting_id
    end
  end

  def down do
    # Add voting_id back to opinions
    alter table(:opinions) do
      add :voting_id, references(:votings, on_delete: :delete_all)
    end

    # Restore data from junction table
    execute """
    UPDATE opinions
    SET voting_id = (
      SELECT voting_id
      FROM opinions_votings
      WHERE opinions_votings.opinion_id = opinions.id
      LIMIT 1
    )
    WHERE EXISTS (
      SELECT 1
      FROM opinions_votings
      WHERE opinions_votings.opinion_id = opinions.id
    )
    """

    # Drop junction table
    drop table(:opinions_votings)
  end
end
