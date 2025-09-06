defmodule YouCongress.Repo.Migrations.AddYearToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :year, :integer
    end

    create index(:opinions, [:year])
  end
end
