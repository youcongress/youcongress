defmodule YouCongress.Repo.Migrations.AddOpinionsCountToStatements do
  use Ecto.Migration

  def change do
    alter table(:statements) do
      add :opinions_count, :integer, default: 0, null: false
    end

    # Populate existing counts
    execute """
    UPDATE statements s
    SET opinions_count = (
      SELECT COUNT(*)
      FROM opinions_statements os
      WHERE os.statement_id = s.id
    )
    """, ""
  end
end
