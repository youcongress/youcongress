defmodule YouCongress.Opinions.Opinion do
  @moduledoc """
  The schema for opinions/comments/quotes.
  """

  use Ecto.Schema
  use Ancestry, repo: YouCongress.Repo

  import Ecto.Changeset

  schema "opinions" do
    field :source_url, :string
    field :content, :string
    field :twin, :boolean, default: false
    field :ancestry, :string

    belongs_to :author, YouCongress.Authors.Author
    belongs_to :user, YouCongress.Accounts.User
    belongs_to :vote, YouCongress.Votes.Vote
    belongs_to :voting, YouCongress.Votings.Voting

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [
      :content,
      :source_url,
      :twin,
      :vote_id,
      :author_id,
      :user_id,
      :voting_id,
      :ancestry
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
end
