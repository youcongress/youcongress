defmodule YouCongress.Repo.Migrations.DeleteVotesOpinion do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      remove :opinion
    end
  end
end
