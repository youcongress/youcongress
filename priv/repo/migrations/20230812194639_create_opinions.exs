defmodule YouCongress.Repo.Migrations.CreateOpinions do
  use Ecto.Migration

  def change do
    create table(:opinions) do
      add :opinion, :text, null: false
      add :author_id, references(:authors, on_delete: :delete_all), null: false
      add :voting_id, references(:votings, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:opinions, [:author_id])
    create index(:opinions, [:voting_id])
  end
end
