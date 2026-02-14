defmodule YouCongress.Repo.Migrations.CreateVerifications do
  use Ecto.Migration

  def up do
    create table(:verifications) do
      add :opinion_id, references(:opinions, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :comment, :text, null: false

      timestamps()
    end

    create unique_index(:verifications, [:opinion_id, :user_id])
    create index(:verifications, [:user_id])

    alter table(:opinions) do
      add :verification_status, :string
    end

    # Migrate existing verified opinions into verifications table
    execute """
    INSERT INTO verifications (opinion_id, user_id, status, comment, inserted_at, updated_at)
    SELECT id, verified_by_user_id, 'verified', 'Migrated from legacy verification', verified_at, verified_at
    FROM opinions
    WHERE verified_at IS NOT NULL AND verified_by_user_id IS NOT NULL
    """

    # Update cached verification_status on opinions
    execute """
    UPDATE opinions SET verification_status = 'verified'
    WHERE verified_at IS NOT NULL AND verified_by_user_id IS NOT NULL
    """
  end

  def down do
    alter table(:opinions) do
      remove :verification_status
    end

    drop table(:verifications)
  end
end
