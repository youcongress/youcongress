defmodule YouCongress.Repo.Migrations.AddVotingIdToOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      add :voting_id, :integer
    end
  end
end
