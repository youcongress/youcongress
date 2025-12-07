defmodule YouCongress.Repo.Migrations.DropAnswersTable do
  use Ecto.Migration

  def up do
    drop table(:answers)
  end

  def down do
    create table(:answers) do
      add :response, :string

      timestamps()
    end
  end
end
