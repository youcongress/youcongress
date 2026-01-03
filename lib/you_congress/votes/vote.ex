defmodule YouCongress.Votes.Vote do
  @moduledoc """
  Define Vote schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Statements.Statement
  alias YouCongress.Opinions.Opinion

  schema "votes" do
    field :direct, :boolean, default: true
    field :twin, :boolean, default: false
    field :answer, Ecto.Enum, values: [:for, :against, :abstain]

    belongs_to :author, Author
    belongs_to :statement, Statement
    # opinion_id links to the main opinion
    # authors can have more than one opinion per statement, but at the moment we only display one
    belongs_to :opinion, Opinion

    timestamps()
  end

  @type t :: %__MODULE__{
          direct: boolean(),
          twin: boolean(),
          author_id: integer(),
          statement_id: integer(),
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
      :statement_id,
      :answer,
      :opinion_id
    ])
    |> validate_required([:author_id, :statement_id])
    |> unique_constraint([:author_id, :statement_id])
  end
end
