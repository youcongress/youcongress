defmodule YouCongress.Repo.Migrations.AddModelToVerifications do
  use Ecto.Migration

  def change do
    alter table(:verifications) do
      add :model, :string, default: "human"
    end
  end
end
