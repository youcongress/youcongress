defmodule YouCongress.HallsVotings.HallVoting do
  @moduledoc """
  HallVoting schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votings.Voting
  alias YouCongress.Halls.Hall

  schema "halls_votings" do
    belongs_to(:voting, Voting)
    belongs_to(:hall, Hall)
  end

  @doc false
  def changeset(voting_hall, attrs) do
    voting_hall
    |> cast(attrs, [:voting_id, :hall_id])
    |> validate_required([:voting_id, :hall_id])
  end
end
