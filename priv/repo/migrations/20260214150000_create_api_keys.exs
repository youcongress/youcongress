defmodule YouCongress.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token, :string, null: false
      add :scope, :string, null: false, default: "read"

      timestamps()
    end

    create index(:api_keys, [:user_id])
    create unique_index(:api_keys, [:token])
  end
end
