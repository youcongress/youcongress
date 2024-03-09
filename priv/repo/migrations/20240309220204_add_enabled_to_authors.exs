defmodule YouCongress.Repo.Migrations.AddEnabledToAuthors do
  use Ecto.Migration

  def change do
    alter table(:authors) do
      add :enabled, :boolean, default: true, null: false
    end
  end
end
