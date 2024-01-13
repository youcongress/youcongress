defmodule YouCongress.Votings.Voting do
  @moduledoc """
  Define Voting schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote

  @max_title_slug_size 70

  schema "votings" do
    field :title, :string
    field :generating_left, :integer, default: 0
    field :slug, :string

    has_many :votes, Vote
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  @type t :: %__MODULE__{
          title: String.t(),
          generating_left: integer(),
          votes: [Vote.t()],
          user: YouCongress.Accounts.User.t(),
          user_id: integer() | nil,
          slug: String.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [:title, :generating_left, :user_id, :slug])
    |> validate_required([:title])
    |> unique_constraint(:title)
    |> generate_slug_if_empty()
    |> unique_constraint(:slug)
  end

  defp generate_slug_if_empty(changeset) do
    if get_field(changeset, :slug) do
      changeset
    else
      title = get_field(changeset, :title)
      put_change(changeset, :slug, new_slug(title))
    end
  end

  defp new_slug(title) when is_binary(title) do
    title
    |> Slug.slugify()
    |> String.slice(0..(@max_title_slug_size - 1))
  end

  defp new_slug(_), do: nil
end
