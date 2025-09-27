defmodule YouCongress.Repo.Migrations.AddVerifiedByUserIdToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :verified_by_user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:opinions, [:verified_by_user_id])
  end
end
