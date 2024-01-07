defmodule YouCongress.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations) do
      add :twitter_username, :string
      add :user_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:invitations, [:user_id])
    create unique_index(:invitations, [:twitter_username])
  end
end
