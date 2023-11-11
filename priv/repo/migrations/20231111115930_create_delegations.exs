defmodule YouCongress.Repo.Migrations.CreateDelegations do
  use Ecto.Migration

  def change do
    create table(:delegations) do
      add :deleguee_id, references(:authors, on_delete: :delete_all), null: false
      add :delegate_id, references(:authors, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:delegations, [:deleguee_id])
    create index(:delegations, [:delegate_id])
    create unique_index(:delegations, [:delegate_id, :deleguee_id])
  end
end

#
