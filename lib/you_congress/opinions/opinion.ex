defmodule YouCongress.Opinions.Opinion do
  @moduledoc """
  The schema for opinions/c/quotes.
  """

  use Ecto.Schema
  use Ancestry, repo: YouCongress.Repo

  import Ecto.Changeset

  schema "opinions" do
    field :source_url, :string
    field :content, :string
    field :twin, :boolean, default: false

    field :verification_status, Ecto.Enum,
      values: [:verified, :endorsed, :disputed, :unverifiable]

    field :ancestry, :string
    field :descendants_count, :integer, default: 0
    field :likes_count, :integer, default: 0
    field :year, :integer

    belongs_to :author, YouCongress.Authors.Author
    belongs_to :user, YouCongress.Accounts.User
    has_many :verifications, YouCongress.Verifications.Verification
    has_many :opinion_statements, YouCongress.OpinionsStatements.OpinionStatement

    many_to_many(
      :statements,
      YouCongress.Statements.Statement,
      join_through: "opinions_statements",
      join_keys: [opinion_id: :id, statement_id: :id],
      on_replace: :delete
    )

    has_many :likes, YouCongress.Likes.Like

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [
      :content,
      :source_url,
      :twin,
      :verification_status,
      :author_id,
      :user_id,
      :ancestry,
      :descendants_count,
      :likes_count,
      :year
    ])
    |> validate_required([:content, :twin])
    |> validate_source_url_if_present()
  end

  defp validate_source_url_if_present(changeset) do
    case get_field(changeset, :source_url) do
      nil ->
        changeset

      source_url ->
        if starts_with_http(source_url) do
          changeset
        else
          add_error(changeset, :source_url, "is not a valid URL")
        end
    end
  end

  defp starts_with_http("http://" <> _), do: true
  defp starts_with_http("https://" <> _), do: true
  defp starts_with_http(_), do: false

  def path_str(%{ancestry: nil, id: id}), do: "#{id}"
  def path_str(%{ancestry: ancestry, id: id}), do: "#{ancestry}/#{id}"

  @doc """
  Gets the first statement for an opinion (replacement for primary_statement).
  """
  def first_statement(%{statements: [statement | _]}) when not is_nil(statement), do: statement
  def first_statement(_), do: nil

  @doc """
  Returns true if the opinion has a verification status set.
  """
  def verified?(%{verification_status: nil}), do: false
  def verified?(%{verification_status: status}) when not is_nil(status), do: true
  def verified?(_), do: false
end
