defmodule YouCongress.Repo.Migrations.AddCouncilInvitations do
  use Ecto.Migration

  def change do
    alter table(:councils) do
      add :invited_by_id, references(:authors, on_delete: :nilify_all)
    end

    create table(:council_invitations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :note, :text
      add :status, :string, null: false, default: "queued"
      timestamps()
    end

    create unique_index(:council_invitations, [:user_id, :email])
    create index(:councils, [:invited_by_id])
  end
end
