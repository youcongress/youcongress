defmodule YouCongress.Repo.Migrations.DropVerificationsUniqueIndex do
  use Ecto.Migration

  def up do
    drop unique_index(:verifications, [:opinion_id, :user_id])
    create index(:verifications, [:opinion_id])
  end

  def down do
    drop index(:verifications, [:opinion_id])
    create unique_index(:verifications, [:opinion_id, :user_id])
  end
end
