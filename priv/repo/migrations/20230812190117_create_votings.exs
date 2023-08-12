defmodule YouCongress.Repo.Migrations.CreateVotings do
  use Ecto.Migration

  def change do
    create table(:votings) do
      add :title, :string, null: false

      timestamps()
    end

    create unique_index(:votings, [:title])
  end
end
