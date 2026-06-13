defmodule YouCongress.VoteVerifications.VoteVerification do
  @moduledoc """
  Schema for vote-answer verifications.

  Records whether a vote's answer (for/against/abstain) is correct for the
  statement it is cast on, given its sourced opinion.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "vote_verifications" do
    field :status, Ecto.Enum,
      values: [
        :verified,
        :ai_verified,
        :ai_unverifiable,
        :endorsed,
        :disputed,
        :unverifiable,
        :unverified
      ]

    field :comment, :string
    field :model, :string, default: "human"

    belongs_to :vote, YouCongress.Votes.Vote
    # The opinion the vote referenced at verification time. A verification only
    # applies while the vote still points to this opinion.
    belongs_to :opinion, YouCongress.Opinions.Opinion
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  def changeset(verification, attrs) do
    verification
    |> cast(attrs, [:vote_id, :opinion_id, :user_id, :status, :comment, :model])
    |> validate_required([:vote_id, :user_id, :status])
    |> foreign_key_constraint(:vote_id)
    |> foreign_key_constraint(:opinion_id)
    |> foreign_key_constraint(:user_id)
  end
end
