defmodule YouCongress.Repo.Migrations.AddUniqueIndexInVotesAuthorIdVotingIdAnswerId do
  use Ecto.Migration

  def change do
    create unique_index(:votes, [:author_id, :voting_id, :answer_id])
  end
end
