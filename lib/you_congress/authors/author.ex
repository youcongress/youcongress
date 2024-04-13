defmodule YouCongress.Authors.Author do
  @moduledoc """
  Defines Author schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "authors" do
    # twitter fields
    field :name, :string
    field :twitter_id_str, :string
    field :profile_image_url, :string
    field :description, :string
    field :followers_count, :integer
    field :friends_count, :integer
    field :verified, :boolean
    field :location, :string
    field :twitter_username, :string
    # bio is AI-generated for twins and is displayed instead of description if present
    field :bio, :string
    # country is AI-generated for twins and is displayed location if present
    field :country, :string
    field :wikipedia_url, :string
    # twin_origin indicates if the author started as a digital twin
    # or if GPT returned an opinion while being disabled (see digital_twins.ex)
    field :twin_origin, :boolean, default: true
    field :twin_enabled, :boolean, default: true

    has_many :votes, YouCongress.Votes.Vote

    timestamps()
  end

  @doc false
  def changeset(author, attrs) do
    author
    |> cast(attrs, [
      :name,
      :bio,
      :wikipedia_url,
      :twitter_username,
      :country,
      :twin_origin,
      :twitter_id_str,
      :profile_image_url,
      :twin_enabled,
      :description,
      :followers_count,
      :friends_count,
      :verified,
      :location
    ])
    |> validate_required([:twin_origin])
    |> validate_required_if_twin_origin()
    |> unique_constraint(:twitter_username)
    |> unique_constraint(:wikipedia_url)
    |> validate_wikipedia_url_if_present()
  end

  def validate_required_if_twin_origin(changeset) do
    if get_field(changeset, :twin_origin) do
      validate_required(changeset, [:name, :bio, :country])
    else
      changeset
    end
  end

  defp validate_wikipedia_url_if_present(changeset) do
    case get_field(changeset, :wikipedia_url) do
      nil ->
        changeset

      wikipedia_url ->
        if starts_with_http(wikipedia_url) do
          changeset
        else
          add_error(changeset, :wikipedia_url, "is not a valid URL")
        end
    end
  end

  defp starts_with_http("http" <> _), do: true
  defp starts_with_http(_), do: false
end
