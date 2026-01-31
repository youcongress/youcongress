defmodule YouCongress.Repo.Migrations.AddIsMainToHallsStatements do
  use Ecto.Migration

  def change do
    alter table(:halls_statements) do
      add :is_main, :boolean, default: false, null: false
    end
  end
end
