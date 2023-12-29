defmodule YouCongress.Repo.Migrations.AddUserIdToVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      add :user_id, references(:users), null: true
    end
  end
end
