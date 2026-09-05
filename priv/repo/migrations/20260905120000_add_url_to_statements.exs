defmodule YouCongress.Repo.Migrations.AddUrlToStatements do
  use Ecto.Migration

  def change do
    alter table(:statements) do
      add :url, :text
    end
  end
end
