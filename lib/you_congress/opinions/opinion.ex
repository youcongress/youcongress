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
    field :ancestry, :string
    field :descendants_count, :integer, default: 0
    field :likes_count, :integer, default: 0

    belongs_to :author, YouCongress.Authors.Author
    belongs_to :user, YouCongress.Accounts.User

    has_many :opinion_votings, YouCongress.OpinionsVotings.OpinionVoting

    many_to_many(
      :votings,
      YouCongress.Votings.Voting,
      join_through: YouCongress.OpinionsVotings.OpinionVoting,
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
      :author_id,
      :user_id,
      :ancestry,
      :descendants_count,
      :likes_count
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

  defp starts_with_http("http" <> _), do: true
  defp starts_with_http(_), do: false

  def path_str(%{ancestry: nil, id: id}), do: "#{id}"
  def path_str(%{ancestry: ancestry, id: id}), do: "#{ancestry}/#{id}"

  @doc """
  Gets the first voting for an opinion (replacement for primary_voting).
  """
  def first_voting(%{votings: [voting | _]}) when not is_nil(voting), do: voting
  def first_voting(_), do: nil
end
