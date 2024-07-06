defmodule YouCongress.Repo.Migrations.AddDescendantsCountToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :descendants_count, :integer, default: 0
    end
  end
end
