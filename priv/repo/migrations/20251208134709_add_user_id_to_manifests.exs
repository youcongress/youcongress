defmodule YouCongress.Repo.Migrations.AddUserIdToManifests do
  use Ecto.Migration

  def change do
    alter table(:manifests) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:manifests, [:user_id])
  end
end
