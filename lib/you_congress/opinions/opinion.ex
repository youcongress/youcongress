defmodule YouCongress.Opinions.Opinion do
  @moduledoc """
  Define Opinion schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Opinions.Answers.Answer
  alias YouCongress.Votings.Voting

  schema "opinions" do
    field :opinion, :string

    belongs_to :author, Author
    belongs_to :voting, Voting
    belongs_to :answer, Answer

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [:opinion, :author_id, :voting_id, :answer_id])
    |> validate_required([:opinion, :author_id, :voting_id, :answer_id])
    |> unique_constraint(:opinion)
    |> unique_constraint(:author_id)
    |> unique_constraint(:voting_id)
    |> unique_constraint(:answer_id)
  end
end
