defmodule YouCongress.Repo.Migrations.RemoveGeneratingColumnsFromVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      remove :generating_left, :integer
      remove :generating_total, :integer
    end
  end
end
