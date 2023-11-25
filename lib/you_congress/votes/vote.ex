defmodule YouCongress.Votes.Vote do
  @moduledoc """
  Define Vote schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Votes.Answers.Answer
  alias YouCongress.Votings.Voting

  schema "votes" do
    field :opinion, :string

    belongs_to :author, Author
    belongs_to :voting, Voting
    belongs_to :answer, Answer

    timestamps()
  end

  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:opinion, :author_id, :voting_id, :answer_id])
    |> validate_required([:author_id, :voting_id, :answer_id])
    |> unique_constraint(:author_id)
    |> unique_constraint(:voting_id)
    |> unique_constraint(:answer_id)
  end
end
