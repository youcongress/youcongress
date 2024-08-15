defmodule YouCongress.Repo.Migrations.CreateLikesTable do
  use Ecto.Migration

  def change do
    create table(:likes) do
      add :opinion_id, :integer, null: false
      add :user_id, :integer, null: false

      timestamps()
    end

    create index(:likes, [:opinion_id, :user_id], unique: true)
  end
end
