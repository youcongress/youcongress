defmodule YouCongress.Repo.Migrations.CreateAnswers do
  use Ecto.Migration

  def change do
    create table(:answers) do
      add :response, :string, null: false

      timestamps()
    end
  end
end
