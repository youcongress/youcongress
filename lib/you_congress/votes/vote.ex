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
    field :direct, :boolean, default: true
    field :twin, :boolean, default: false

    belongs_to :author, Author
    belongs_to :voting, Voting
    belongs_to :answer, Answer

    timestamps()
  end

  @type t :: %__MODULE__{
          opinion: String.t() | nil,
          direct: boolean(),
          twin: boolean(),
          author_id: integer(),
          voting_id: integer(),
          answer_id: integer(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }
  @doc false
  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:direct, :twin, :opinion, :author_id, :voting_id, :answer_id])
    |> validate_required([:author_id, :voting_id, :answer_id])
    |> unique_constraint([:author_id, :voting_id])
  end
end
