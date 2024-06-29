defmodule YouCongress.Opinions.Opinion do
  @moduledoc """
  The schema for opinions/comments/quotes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "opinions" do
    field :source_url, :string
    field :content, :string
    field :twin, :boolean, default: false
    field :parent_id, :id

    belongs_to :author, YouCongress.Authors.Author
    belongs_to :user, YouCongress.Accounts.User
    belongs_to :vote, YouCongress.Votes.Vote
    belongs_to :voting, YouCongress.Votings.Voting

    timestamps()
  end

  @doc false
  def changeset(opinion, attrs) do
    opinion
    |> cast(attrs, [:content, :source_url, :twin, :vote_id, :author_id, :user_id, :voting_id])
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
end
