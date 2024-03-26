defmodule YouCongress.Repo.Migrations.CreateOpinions do
  use Ecto.Migration

  def change do
    create table(:opinions) do
      add :content, :text, null: false
      add :source_url, :string
      add :twin, :boolean, default: false, null: false
      add :author_id, references(:authors, on_delete: :delete_all)
      add :user_id, references(:users, on_delete: :delete_all)
      add :vote_id, references(:votes, on_delete: :delete_all)

      timestamps()
    end

    create index(:opinions, [:author_id])
    create index(:opinions, [:user_id])
    create index(:opinions, [:vote_id])

    alter table(:votes) do
      add :opinion_id, references(:opinions, on_delete: :nullify)
    end
  end
end
