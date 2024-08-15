defmodule YouCongress.Repo.Migrations.AddLikesCountToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :likes_count, :integer, default: 0
    end
  end
end
