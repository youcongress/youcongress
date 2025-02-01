defmodule YouCongress.HallsVotings do
  @moduledoc """
  Relationships between Halls and Votings.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Halls
  alias YouCongress.Halls.Hall
  alias YouCongress.HallsVotings.HallVoting

  def sync! do
    Enum.each(Votings.list_votings(), fn voting -> sync!(voting.id) end)
  end

  @doc """
  Updates the halls associated with a voting.

  ## Raises
    - Raises an error if the voting does not exist or if there's an issue updating the voting's halls.
  """
  def sync!(voting_id, tags \\ nil) do
    voting = Votings.get_voting!(voting_id, preload: [:halls])
    tags = tags || Halls.classify!(voting.title)
    {:ok, halls} = Halls.list_or_create_by_names(tags)

    link(voting, halls)
  end

  @spec link(Voting.t(), [Hall.t()]) :: {:ok, Voting.t()} | {:error, Ecto.Changeset.t()}
  defp link(voting, halls) do
    voting_changeset =
      voting
      |> Voting.changeset(%{})
      |> Ecto.Changeset.put_assoc(:halls, halls)

    Repo.update(voting_changeset)
  end

  def delete_halls_votings(%Voting{id: voting_id}) do
    Repo.delete_all(from h in HallVoting, where: h.voting_id == ^voting_id)
  end

  def get_random_voting(hall_name) do
    from(v in Voting,
      join: h in assoc(v, :halls),
      where: h.name == ^hall_name,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  def get_random_votings(hall_name, limit, exclude_ids \\ []) do
    from(v in Voting,
      join: h in assoc(v, :halls),
      where: h.name == ^hall_name and v.id not in ^exclude_ids,
      order_by: fragment("RANDOM()"),
      limit: ^limit
    )
    |> Repo.all()
  end
end
