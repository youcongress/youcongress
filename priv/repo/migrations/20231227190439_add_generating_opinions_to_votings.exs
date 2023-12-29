defmodule YouCongress.Repo.Migrations.AddGeneratingLeftToVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      add :generating_left, :integer, default: 0, null: false
    end
  end
end
