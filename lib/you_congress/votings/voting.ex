defmodule YouCongress.Votings.Voting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "votings" do
    field :title, :string

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
