defmodule YouCongress.Repo.Migrations.CreateManifestsTables do
  use Ecto.Migration

  def change do
    create table(:manifests) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :active, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:manifests, [:slug])

    create table(:manifest_sections) do
      add :manifest_id, references(:manifests, on_delete: :delete_all), null: false
      add :body, :text, null: false
      add :voting_id, references(:votings, on_delete: :nilify_all)
      add :weight, :integer, default: 0, null: false

      timestamps()
    end

    create index(:manifest_sections, [:manifest_id])
    create index(:manifest_sections, [:voting_id])

    create table(:manifest_signatures) do
      add :manifest_id, references(:manifests, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:manifest_signatures, [:manifest_id, :user_id])
    create index(:manifest_signatures, [:user_id])
  end
end
