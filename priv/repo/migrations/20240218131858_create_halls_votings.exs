defmodule YouCongress.Repo.Migrations.CreateHallsVotings do
  use Ecto.Migration

  def change do
    create table(:halls_votings) do
      add :hall_id, references(:halls)
      add :voting_id, references(:votings)
    end

    create unique_index(:halls_votings, [:hall_id, :voting_id])
    create index(:halls_votings, [:hall_id])
    create index(:halls_votings, [:voting_id])
  end
end
