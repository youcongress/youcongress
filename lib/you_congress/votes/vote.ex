defmodule YouCongress.Votes.Vote do
  @moduledoc """
  Define Vote schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Votings.Voting
  alias YouCongress.Opinions.Opinion

  schema "votes" do
    field :direct, :boolean, default: true
    field :twin, :boolean, default: false
    field :answer, Ecto.Enum, values: [:for, :against, :abstain]

    belongs_to :author, Author
    belongs_to :voting, Voting
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
          answer: :for | :against | :abstain,
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
      :answer,
      :opinion_id
    ])
    |> validate_required([:author_id, :voting_id])
    |> unique_constraint([:author_id, :voting_id])
  end
end
