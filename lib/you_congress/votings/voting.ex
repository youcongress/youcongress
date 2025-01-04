defmodule YouCongress.Votings.Voting do
  @moduledoc """
  Define Voting schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote
  alias YouCongress.Votings
  alias YouCongress.Halls.Hall
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Accounts.User

  @max_title_slug_size 30

  schema "votings" do
    field :title, :string
    field :generating_total, :integer, default: 0
    field :generating_left, :integer, default: 0
    field :slug, :string
    field :opinion_likes_count, :integer, default: 0

    has_many :votes, Vote
    has_many :opinions, Opinion

    many_to_many(
      :halls,
      Hall,
      join_through: "halls_votings",
      on_replace: :delete
    )

    belongs_to :user, User

    timestamps()
  end

  @type t :: %__MODULE__{
          title: String.t(),
          generating_left: integer(),
          votes: [Vote.t()],
          user: User.t(),
          user_id: integer() | nil,
          slug: String.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [
      :title,
      :generating_left,
      :generating_total,
      :user_id,
      :slug,
      :opinion_likes_count,
      :updated_at
    ])
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
      put_change(changeset, :slug, new_unique_slug(title))
    end
  end

  defp new_unique_slug(nil), do: nil
  defp new_unique_slug(""), do: ""

  defp new_unique_slug(title) do
    slug = new_slug(title)

    case Votings.get_by(slug: slug) do
      nil -> slug
      _ -> "#{slug}-#{random_string()}"
    end
  end

  defp random_string, do: :crypto.strong_rand_bytes(1) |> Base.encode16()

  defp new_slug(title) when is_binary(title) do
    title
    |> Slug.slugify()
    |> remove_some_words()
    |> String.slice(0..(@max_title_slug_size - 1))
    |> String.replace(~r/\-$/, "")
  end

  defp new_slug(_), do: nil

  defp words do
    ~w(a an and as at but by for in nor of on or so the to up yet would should will shall could can he she it them we with consider accept that this those these)
  end

  defp remove_some_words(slug) do
    words()
    |> Enum.reduce("-#{slug}", &String.replace(&2, "-#{&1}-", "-"))
    |> String.replace(~r/^\-/, "")
  end
end
