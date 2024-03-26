defmodule YouCongress.Votes.Vote do
  @moduledoc """
  Define Vote schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Votes.Answers.Answer
  alias YouCongress.Votings.Voting
  alias YouCongress.Opinions.Opinion

  schema "votes" do
    field :direct, :boolean, default: true
    field :twin, :boolean, default: false

    belongs_to :author, Author
    belongs_to :voting, Voting
    belongs_to :answer, Answer
    # opinion_id links to the main opinion
    # authors can have more than one opinion per voting, but at the moment we only display one
    belongs_to :opinion, Opinion

    timestamps()
  end

  @type t :: %__MODULE__{
          direct: boolean(),
          twin: boolean(),
          author_id: integer(),
          voting_id: integer(),
          answer_id: integer(),
          opinion_id: integer(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }
  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [
      :direct,
      :twin,
      :author_id,
      :voting_id,
      :answer_id,
      :opinion_id
    ])
    |> validate_required([:author_id, :voting_id, :answer_id])
    |> unique_constraint([:author_id, :voting_id])
  end
end
