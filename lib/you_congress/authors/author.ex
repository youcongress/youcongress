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
    field :google_id, :string
    # bio is AI-generated for twins and is displayed instead of description if present
    field :bio, :string
    field :wikipedia_url, :string
    # twin_origin indicates if the author started as a digital twin
    # or if GPT returned an opinion while being disabled (see digital_twins.ex)
    field :twin_origin, :boolean, default: true
    field :twin_enabled, :boolean, default: true
    field :public_figure, :boolean, default: false

    has_many :votes, YouCongress.Votes.Vote
    belongs_to :country, YouCongress.Countries.Country

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
      :google_id,
      :country_id,
      :twin_origin,
      :twitter_id_str,
      :profile_image_url,
      :twin_enabled,
      :public_figure,
      :description,
      :followers_count,
      :friends_count,
      :verified,
      :location
    ])
    |> validate_required([:twin_origin])
    |> validate_required_if_twin_origin()
    |> unique_constraint(:twitter_username)
    |> unique_constraint(:twitter_id_str)
    |> unique_constraint(:google_id)
    |> unique_constraint(:wikipedia_url)
    |> foreign_key_constraint(:country_id)
    |> validate_wikipedia_url_if_present()
  end

  def profile_changeset(author, attrs, allowed_fields) when is_list(allowed_fields) do
    allowed_fields = Enum.map(allowed_fields, &normalize_profile_field!/1)

    author
    |> cast(attrs, allowed_fields)
    |> foreign_key_constraint(:country_id)
  end

  defp normalize_profile_field!(field) when field in [:name, :bio, :country_id], do: field

  defp normalize_profile_field!(field) when field in ["name", "bio", "country_id"] do
    String.to_existing_atom(field)
  end

  defp normalize_profile_field!(field) do
    raise ArgumentError, "unsupported profile field: #{inspect(field)}"
  end

  def validate_required_if_twin_origin(changeset) do
    if get_field(changeset, :twin_origin) do
      validate_required(changeset, [:name, :bio])
    else
      changeset
    end
  end

  defp validate_wikipedia_url_if_present(changeset) do
    case get_field(changeset, :wikipedia_url) do
      nil ->
        changeset

      wikipedia_url ->
        cond do
          not starts_with_https(wikipedia_url) ->
            add_error(changeset, :wikipedia_url, "must start with https://")

          not contains_wikipedia_wiki(wikipedia_url) ->
            add_error(
              changeset,
              :wikipedia_url,
              "must be a valid Wikipedia URL containing '.wikipedia.org/wiki/'"
            )

          true ->
            changeset
        end
    end
  end

  defp starts_with_https("https://" <> _), do: true
  defp starts_with_https(_), do: false

  defp contains_wikipedia_wiki(url) do
    String.contains?(url, ".wikipedia.org/wiki/")
  end
end
