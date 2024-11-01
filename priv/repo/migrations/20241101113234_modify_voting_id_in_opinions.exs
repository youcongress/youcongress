defmodule YouCongress.Repo.Migrations.ModifyVotingIdInOpinions do
  use Ecto.Migration

  def change do
    alter table(:opinions) do
      modify :voting_id, references(:votings, on_delete: :delete_all), null: false
    end
  end
end
