defmodule YouCongress.Repo.Migrations.AddHideCreatorAttributionToReconsiderations do
  use Ecto.Migration

  def change do
    alter table(:reconsiderations) do
      add :hide_creator_attribution, :boolean, null: false, default: false
    end
  end
end
