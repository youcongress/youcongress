defmodule YouCongress.Authors.Author do
  @moduledoc """
  Defines Author schema.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "authors" do
    field :name, :string
    field :bio, :string
    field :country, :string
    field :twitter_username, :string
    field :wikipedia_url, :string
    field :is_twin, :boolean, default: true
    field :twitter_id_str, :string
    field :profile_image_url, :string
    field :description, :string
    field :followers_count, :integer
    field :friends_count, :integer
    field :verified, :boolean
    field :location, :string

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
