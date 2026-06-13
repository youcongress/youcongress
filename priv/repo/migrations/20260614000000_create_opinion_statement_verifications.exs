defmodule YouCongress.Repo.Migrations.CreateOpinionStatementVerifications do
  use Ecto.Migration

  def change do
    create table(:opinion_statement_verifications) do
      add :opinion_statement_id, references(:opinions_statements, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :comment, :text, null: false
      add :model, :string, default: "human"

      timestamps()
    end

    create index(:opinion_statement_verifications, [:opinion_statement_id])
    create index(:opinion_statement_verifications, [:user_id])

    alter table(:opinions_statements) do
      add :verification_status, :string
    end
  end
end
