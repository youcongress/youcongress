defmodule YouCongress.Repo.Migrations.PopulateOpinionsVotingId do
  use Ecto.Migration

  alias YouCongress.Opinions
  alias YouCongress.Votes

  def up do
    # Enum.each(Opinions.list_opinions(), fn opinion ->
    #   vote = Votes.get_vote!(opinion.vote_id)
    #   {:ok, _} = Opinions.update_opinion(opinion, %{voting_id: vote.voting_id})
    # end)

    alter table(:opinions) do
      modify :voting_id, :integer, null: false
    end
  end

  def down do
    alter table(:opinions) do
      modify :voting_id, :integer, null: true
    end

    # Enum.each(Opinions.list_opinions(), fn opinion ->
    #   {:ok, _} = Opinions.update_opinion(opinion, %{voting_id: nil})
    # end)
  end
end
