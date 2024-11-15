defmodule YouCongress.Repo.Migrations.AddOpinionLikesCountToVotings do
  use Ecto.Migration

  def change do
    alter table(:votings) do
      add :opinion_likes_count, :integer, default: 0, null: false
    end
  end
end
