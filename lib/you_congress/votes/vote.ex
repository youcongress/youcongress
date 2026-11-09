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
    field :revision, :integer, default: 1
    field :origin, :string, default: "legacy"
    field :cast_by_user_id, :id
    field :twin, :boolean, default: false
    field :answer, Ecto.Enum, values: [:for, :against, :abstain]

    field :verification_status, Ecto.Enum,
      values: [:verified, :ai_verified, :ai_unverifiable, :endorsed, :disputed, :unverifiable]

    belongs_to :author, Author
    belongs_to :statement, Statement
    # opinion_id links to the main opinion
    # authors can have more than one opinion per statement, but at the moment we only display one
    belongs_to :opinion, Opinion
    has_many :verifications, YouCongress.VoteVerifications.VoteVerification
    field :alternate_opinions, {:array, :map}, virtual: true, default: []

    timestamps()
  end

  @doc "Exclude pending Council projections while retaining their stored timestamps."
  def current(query \\ __MODULE__) do
    import Ecto.Query

    from v in query,
      where:
        v.direct or
          fragment(
            "NOT EXISTS (SELECT 1 FROM councils c WHERE c.author_id = ?) OR EXISTS (SELECT 1 FROM council_decisions d JOIN councils c ON c.author_id = d.author_id WHERE d.author_id = ? AND d.statement_id = ? AND d.council_version = c.version AND d.answer = ?::text)",
            v.author_id,
            v.author_id,
            v.statement_id,
            v.answer
          )
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
      :origin,
      :cast_by_user_id,
      :twin,
      :author_id,
      :statement_id,
      :answer,
      :opinion_id,
      :verification_status
    ])
    |> validate_required([:author_id, :statement_id])
    |> unique_constraint([:author_id, :statement_id])
  end
end
