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
    field :is_twin, :boolean, default: true
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
      :is_twin,
      :twitter_id_str,
      :profile_image_url,
      :twin_enabled,
      :description,
      :followers_count,
      :friends_count,
      :verified,
      :location
    ])
    |> validate_required([:is_twin])
    |> validate_required_if_is_twin()
  end

  def validate_required_if_is_twin(changeset) do
    if get_field(changeset, :is_twin) do
      changeset
      |> validate_required([:name, :bio, :country])
      |> unique_constraint(:twitter_username)
      |> unique_constraint(:wikipedia_url)
    else
      changeset
    end
  end
end
