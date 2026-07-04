defmodule YouCongress.Repo.Migrations.AddSynthesisToStatements do
  use Ecto.Migration

  def change do
    alter table(:statements) do
      add :synthesis, :map
      add :synthesis_generated_at, :utc_datetime
      add :synthesis_quotes_count, :integer
    end
  end
end
