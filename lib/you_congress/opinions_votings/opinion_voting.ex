defmodule YouCongress.OpinionsVotings.OpinionVoting do
  @moduledoc """
  Join schema for the many-to-many relationship between opinions and votings.
  Includes user_id to track who associated the opinion with the voting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votings.Voting
  alias YouCongress.Accounts.User

  schema "opinions_votings" do
    belongs_to :opinion, Opinion
    belongs_to :voting, Voting
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(opinion_voting, attrs) do
    opinion_voting
    |> cast(attrs, [:opinion_id, :voting_id, :user_id])
    |> validate_required([:opinion_id, :voting_id, :user_id])
    |> unique_constraint([:opinion_id, :voting_id])
    |> foreign_key_constraint(:opinion_id)
    |> foreign_key_constraint(:voting_id)
    |> foreign_key_constraint(:user_id)
  end
end
