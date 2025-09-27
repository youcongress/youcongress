defmodule YouCongress.Repo.Migrations.AddVerifiedAtToOpinions do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      add :verified_at, :utc_datetime
    end

    # Migrate existing verified opinions to have verified_at = now
    execute("UPDATE opinions SET verified_at = NOW() WHERE is_verified = TRUE")
  end

  def down do
    alter table(:opinions) do
      remove :verified_at
    end
  end
end

