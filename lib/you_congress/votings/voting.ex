defmodule YouCongress.Votings.Voting do
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Opinions.Opinion

  schema "votings" do
    field :title, :string

    has_many :opinions, Opinion

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
