defmodule YouCongress.Repo.Migrations.RemoveIsVerifiedFromOpinions do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      remove :is_verified
    end
  end

  def down do
    alter table(:opinions) do
      add :is_verified, :boolean, default: false, null: false
    end

    # Restore is_verified based on verified_at
    execute("UPDATE opinions SET is_verified = TRUE WHERE verified_at IS NOT NULL")
  end
end
