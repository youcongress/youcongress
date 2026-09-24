defmodule YouCongress.Authors.Author do
  @moduledoc """
  Defines Author schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @username_format ~r/\A[a-z0-9][a-z0-9_]*\z/
  @reserved_usernames ~w(
    a about assets auth authors c contact dataset dev email-login-waiting-list explore
    fact-checker faq h home images landing llms.txt log_in log_out mcp mcp-tools oban p
    privacy-policy reset_password robots.txt settings sign_up sim sitemap.xml terms users v
    verifications waiting_list welcome x
  )

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
    field :username, :string
    field :google_id, :string
    # bio is AI-generated for twins and is displayed instead of description if present
    field :bio, :string
    field :wikipedia_url, :string
    # Wikidata entity id (e.g. "Q42") derived from the wikipedia_url
    field :wikidata, :string
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
      :wikidata,
      :twitter_username,
      :username,
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
    |> validate_username()
    |> unique_constraint(:twitter_username)
    |> unique_constraint(:twitter_username, name: :authors_twitter_url_index)
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
    |> validate_username()
    |> foreign_key_constraint(:country_id)
  end

  defp normalize_profile_field!(field) when field in [:name, :bio, :country_id, :username],
    do: field

  defp normalize_profile_field!(field) when field in ["name", "bio", "country_id", "username"] do
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

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &normalize_username/1)
    |> validate_length(:username, min: 5, max: 15)
    |> validate_format(:username, @username_format,
      message: "may contain only lowercase letters, numbers, and underscores"
    )
    |> validate_exclusion(:username, @reserved_usernames, message: "is reserved")
    |> unique_constraint(:username, name: :authors_username_index)
  end

  defp normalize_username(username) do
    username
    |> String.trim()
    |> String.downcase()
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
