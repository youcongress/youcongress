defmodule YouCongress.Repo.Migrations.AddDirectToVotes do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :direct, :boolean, default: true, null: false
    end
  end
end
