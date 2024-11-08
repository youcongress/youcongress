defmodule YouCongress.Halls.Hall do
  @moduledoc """
  The Hall schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votings.Voting

  @names [
    "ai",
    "spain",
    "eu",
    "us",
    "china",
    "world",
    "law",
    "climate",
    "programming",
    "personal-finance",
    "health",
    "future",
    "gov",
    "ethics"
  ]
  @names_str Enum.join(@names, ",")

  schema "halls" do
    field :name, :string

    many_to_many(
      :votings,
      Voting,
      join_through: "halls_votings",
      on_replace: :delete
    )

    timestamps()
  end

  @doc false
  def changeset(hall, attrs) do
    hall
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end

  def names_str, do: @names_str
end
