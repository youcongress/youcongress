defmodule YouCongress.Repo.Migrations.AddParentIdToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :parent_id, :integer
    end
  end
end
