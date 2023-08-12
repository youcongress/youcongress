defmodule YouCongress.Authors.Author do
  use Ecto.Schema
  import Ecto.Changeset

  schema "authors" do
    field :name, :string
    field :bio, :string
    field :country, :string
    field :twitter_url, :string
    field :wikipedia_url, :string
    field :is_twin, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [:name, :bio, :wikipedia_url, :twitter_url, :country, :is_twin])
    |> validate_required([:name, :bio, :wikipedia_url, :twitter_url, :country, :is_twin])
    |> unique_constraint(:twitter_url)
    |> unique_constraint(:wikipedia_url)
  end
end
