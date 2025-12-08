defmodule YouCongress.Repo.Migrations.AddUserIdToManifestos do
  use Ecto.Migration

  def change do
    alter table(:manifestos) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:manifestos, [:user_id])
  end
end
