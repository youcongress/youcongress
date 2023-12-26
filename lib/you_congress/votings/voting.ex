defmodule YouCongress.Votings.Voting do
  @moduledoc """
  Define Voting schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote

  schema "votings" do
    field :title, :string

    has_many :votes, Vote

    timestamps()
  end

  @type t :: %__MODULE__{
          title: String.t(),
          votes: [Vote.t()],
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> unique_constraint(:title)
  end
end
