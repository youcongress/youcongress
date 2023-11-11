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

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> unique_constraint(:title)
  end
end
