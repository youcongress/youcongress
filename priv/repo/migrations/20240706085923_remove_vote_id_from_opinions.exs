defmodule YouCongress.Repo.Migrations.RemoveVoteIdFromOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      remove :vote_id
    end
  end
end
