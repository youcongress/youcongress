defmodule YouCongress.Repo.Migrations.CreatePendingRegistrationActions do
  use Ecto.Migration

  def change do
    create table(:pending_registration_actions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :payload, :map, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:pending_registration_actions, [:user_id])
    create index(:pending_registration_actions, [:expires_at])
  end
end
