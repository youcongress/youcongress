defmodule YouCongress.Repo.Migrations.CreateRateLimits do
  use Ecto.Migration

  def change do
    create table(:rate_limits) do
      add :scope, :string, null: false
      add :key_hash, :binary, null: false
      add :bucket_start, :utc_datetime, null: false
      add :count, :integer, null: false, default: 1

      timestamps()
    end

    create unique_index(:rate_limits, [:scope, :key_hash, :bucket_start])
    create index(:rate_limits, [:bucket_start])
  end
end
