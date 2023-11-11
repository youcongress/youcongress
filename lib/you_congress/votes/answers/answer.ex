defmodule YouCongress.Votes.Answers.Answer do
  @moduledoc """
  Define Answer schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote

  schema "answers" do
    field :response, :string
    has_many :votes, Vote

    timestamps()
  end

  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [:response])
    |> validate_required([:response])
  end
end
