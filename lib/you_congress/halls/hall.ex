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
    "climate-change",
    "programming",
    "personal-finance",
    "health",
    "future",
    "gov",
    "ethics",
    "democracy",
    "blockchain",
    "cybersecurity",
    "data-privacy",
    "digital-rights",
    "emerging-tech",
    "robotics",
    "space",
    "biotech",
    "democracy",
    "voting-systems",
    "regulations",
    "transparency",
    "local-gov",
    "international-relations",
    "immigration",
    "defense",
    "education-policy",
    "monetary-policy",
    "housing",
    "transportation",
    "education",
    "economics",
    "inequality",
    "social-justice",
    "urban-planning",
    "rural-development",
    "mental-health",
    "public-health",
    "environmental-policy",
    "energy",
    "infrastructure",
    "startups",
    "corporate-governance",
    "market-regulation",
    "innovation-policy",
    "competition",
    "labor-rights",
    "trade",
    "research-policy",
    "science-funding",
    "open-science",
    "ethics-in-research",
    "scientific-collaboration",
    "africa",
    "asia-pacific",
    "latin-america",
    "middle-east",
    "nordic",
    "uk",
    "digital-democracy",
    "food-security",
    "water-management",
    "disaster-preparedness",
    "sustainable-development",
    "tech-ethics",
    "privacy",
    "media",
    "disinformation",
    "nuclear",
    "voting-systems",
    "public-interest-ai",
    "future-of-work",
    "ai-innovation-and-culture",
    "trust-in-ai",
    "ai-governance",
    "ai-safety",
    "ai-alignment",
    "ai-deployment",
    "ai-policy",
    "ai-regulation",
    "ai-ethics",
    "ai-risk",
    "existential-risk",
    "cern-for-ai"
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

  def names, do: @names
end
