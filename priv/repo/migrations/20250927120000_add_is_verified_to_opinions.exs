defmodule YouCongress.Repo.Migrations.AddIsVerifiedToOpinions do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      add :is_verified, :boolean, default: false, null: false
    end

    execute("UPDATE opinions SET is_verified = TRUE WHERE source_url IS NULL")
  end

  def down do
    alter table(:opinions) do
      remove :is_verified
    end
  end
end
