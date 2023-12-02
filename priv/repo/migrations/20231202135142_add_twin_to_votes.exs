defmodule YouCongress.Repo.Migrations.AddTwinToVotes do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      add :twin, :boolean, default: false, null: false
    end
  end
end
