defmodule YouCongress.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :opinion, :text
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :voting_id, references(:votings, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:votes, [:author_id])
    create index(:votes, [:voting_id])
  end
end
