defmodule YouCongress.Repo.Migrations.AddGeneratingTotalToVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      add :generating_total, :integer, default: 0
    end
  end
end
