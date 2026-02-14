defmodule YouCongress.Repo.Migrations.RemoveVerifiedColumnsFromOpinions do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      remove :verified_at
      remove :verified_by_user_id
    end
  end

  def down do
    alter table(:opinions) do
      add :verified_at, :utc_datetime
      add :verified_by_user_id, references(:users, on_delete: :nothing)
    end
  end
end
