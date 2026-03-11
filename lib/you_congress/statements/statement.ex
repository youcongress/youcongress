defmodule YouCongress.Statements.Statement do
  @moduledoc """
  Define Statement schema.

  A statement is a claim or proposal that authors can support, oppose, abstain and add opinions to.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Votes.Vote
  alias YouCongress.Statements
  alias YouCongress.Halls.Hall
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Accounts.User
  alias YouCongress.Halls

  @max_title_slug_size 30

  schema "statements" do
    field :title, :string

    field :slug, :string
    field :opinion_likes_count, :integer, default: 0
    field :opinions_count, :integer, default: 0

    has_many :votes, Vote

    has_many :opinion_statements, YouCongress.OpinionsStatements.OpinionStatement

    many_to_many(
      :opinions,
      Opinion,
      join_through: YouCongress.OpinionsStatements.OpinionStatement,
      on_replace: :delete
    )

    many_to_many(
      :halls,
      Hall,
      join_through: "halls_statements",
      on_replace: :delete
    )

    has_many :halls_statements, YouCongress.HallsStatements.HallStatement

    belongs_to :user, User

    timestamps()
  end

  @type t :: %__MODULE__{
          title: String.t(),
          votes: [Vote.t()],
          user: User.t(),
          user_id: integer() | nil,
          slug: String.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @doc false
  def changeset(statement, attrs) do
    statement
    |> cast(attrs, [
      :title,
      :user_id,
      :slug,
      :opinion_likes_count,
      :opinions_count,
      :updated_at
    ])
    |> validate_required([:title])
    |> unique_constraint(:title)
    |> generate_slug_if_empty()
    |> unique_constraint(:slug)
    |> put_halls(attrs)
  end

  defp put_halls(changeset, %{"halls" => halls}) when is_list(halls) do
    case Halls.list_or_create_by_names(halls) do
      {:ok, halls} -> put_assoc(changeset, :halls, halls)
      :error -> add_error(changeset, :halls, "Invalid halls")
    end
  end

  defp put_halls(changeset, _), do: changeset

  defp generate_slug_if_empty(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        title = get_field(changeset, :title)
        put_change(changeset, :slug, unique_slug_from_title(title))

      slug ->
        # Only ensure uniqueness if the slug actually changed
        if get_change(changeset, :slug) do
          put_change(changeset, :slug, ensure_unique_slug(slug))
        else
          changeset
        end
    end
  end

  defp unique_slug_from_title(nil), do: nil
  defp unique_slug_from_title(""), do: ""

  defp unique_slug_from_title(title) do
    title |> new_slug() |> ensure_unique_slug()
  end

  defp ensure_unique_slug(nil), do: nil
  defp ensure_unique_slug(""), do: ""

  defp ensure_unique_slug(slug) do
    case Statements.get_by(slug: slug) do
      nil -> slug
      _ -> find_unique_slug(slug, 2)
    end
  end

  defp find_unique_slug(base_slug, n) do
    candidate = "#{base_slug}#{n}"

    case Statements.get_by(slug: candidate) do
      nil -> candidate
      _ -> find_unique_slug(base_slug, n + 1)
    end
  end

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
