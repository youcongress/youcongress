defmodule YouCongress.Votings.Voting do
  @moduledoc """
  Define Voting schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote

  schema "votings" do
    field :title, :string
    field :generating_left, :integer, default: 0

    has_many :votes, Vote
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  @type t :: %__MODULE__{
          title: String.t(),
          generating_left: integer(),
          votes: [Vote.t()],
          user: YouCongress.Accounts.User.t(),
          user_id: integer() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [:title, :generating_left, :user_id])
    |> validate_required([:title])
    |> unique_constraint(:title)
  end
end
