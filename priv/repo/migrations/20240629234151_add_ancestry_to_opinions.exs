defmodule YouCongress.Repo.Migrations.AddAncestryToOpinions do
  use Ecto.Migration

  def up do
    alter table(:opinions) do
      modify :parent_id, :string, from: :integer
    end

    rename table(:opinions), :parent_id, to: :ancestry

    create index(:opinions, [:ancestry])
  end

  def down do
    raise "Irreversible migration"
  end
end
