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

    has_many :opinion_votings, YouCongress.Opinions.OpinionVoting

    many_to_many(
      :votings,
      YouCongress.Votings.Voting,
      join_through: YouCongress.Opinions.OpinionVoting,
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
    |> put_votings(attrs)
  end

  defp put_votings(changeset, %{"votings" => votings}) when is_list(votings) do
    put_assoc(changeset, :votings, votings)
  end

  defp put_votings(changeset, %{votings: votings}) when is_list(votings) do
    put_assoc(changeset, :votings, votings)
  end

  # Handle backward compatibility for voting_id
  defp put_votings(changeset, %{"voting_id" => voting_id}) when not is_nil(voting_id) do
    voting = YouCongress.Votings.get_voting!(voting_id)
    put_assoc(changeset, :votings, [voting])
  end

  defp put_votings(changeset, %{voting_id: voting_id}) when not is_nil(voting_id) do
    voting = YouCongress.Votings.get_voting!(voting_id)
    put_assoc(changeset, :votings, [voting])
  end

  defp put_votings(changeset, _), do: changeset

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
  Get the primary voting for an opinion. This is a helper function for backward compatibility.
  Returns the first voting if the opinion is associated with multiple votings.
  """
  def primary_voting(%__MODULE__{} = opinion) do
    case opinion.votings do
      [voting | _] ->
        voting

      [] ->
        nil

      %Ecto.Association.NotLoaded{} ->
        opinion
        |> YouCongress.Repo.preload(:votings)
        |> primary_voting()
    end
  end

  @doc """
  Get the primary voting ID for an opinion. This is a helper function for backward compatibility.
  Returns the first voting ID if the opinion is associated with multiple votings.
  """
  def primary_voting_id(%__MODULE__{} = opinion) do
    case primary_voting(opinion) do
      nil -> nil
      voting -> voting.id
    end
  end
end
