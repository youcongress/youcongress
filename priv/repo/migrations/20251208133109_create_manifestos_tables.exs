defmodule YouCongress.Repo.Migrations.CreateManifestosTables do
  use Ecto.Migration

  def change do
    create table(:manifestos) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :active, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:manifestos, [:slug])

    create table(:manifesto_sections) do
      add :manifesto_id, references(:manifestos, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :voting_id, references(:votings, on_delete: :nilify_all)
      add :weight, :integer, default: 0, null: false

      timestamps()
    end

    create index(:manifesto_sections, [:manifesto_id])
    create index(:manifesto_sections, [:voting_id])

    create table(:manifesto_signatures) do
      add :manifesto_id, references(:manifestos, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:manifesto_signatures, [:manifesto_id, :user_id])
    create index(:manifesto_signatures, [:user_id])
  end
end
