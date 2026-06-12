defmodule YouCongress.Repo.Migrations.AddDescriptionToHalls do
  use Ecto.Migration

  def change do
    alter table(:halls) do
      add :description, :text
    end
  end
end
