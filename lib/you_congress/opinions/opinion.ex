defmodule YouCongress.Opinions.Opinion do
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Authors.Author
  alias YouCongress.Votings.Voting

  schema "opinions" do
    field :opinion, :string

    belongs_to :author, Author
    belongs_to :voting, Voting

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [:opinion, :author_id, :voting_id])
    |> validate_required([:opinion, :author_id, :voting_id])
    |> unique_constraint(:opinion)
    |> unique_constraint(:author_id)
    |> unique_constraint(:voting_id)
  end
end
