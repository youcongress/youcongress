defmodule YouCongress.HallsVotings do
  @moduledoc """
  Relationships between Halls and Votings.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Halls
  alias YouCongress.HallsVotings.HallVoting

  def sync! do
    Enum.each(Votings.list_votings(), fn voting -> sync!(voting.id) end)
  end

  @doc """
  Updates the halls associated with a voting.

  ## Raises
    - Raises an error if the voting does not exist or if there's an issue updating the voting's halls.
  """
  @spec sync!(integer) :: :ok
  def sync!(voting_id) do
    voting = Votings.get_voting!(voting_id, preload: [:halls])

    {:ok, %{tags: tags}} = Halls.classify(voting.title)
    {:ok, halls} = Halls.list_or_create_by_names(tags)

    link!(voting, halls)
  end

  @doc """
  Links a voting to a list of halls.

  ## Parameters
    - `voting`: The voting struct with its **halls preloaded**.
    - `halls`: A list of hall structs to link with the voting.

  ## Raises
    - Raises an error if there's an issue updating the voting's halls.
  """
  @spec link!(Voting.t(), [Hall.t()]) :: :ok
  def link!(voting, halls) do
    voting_changeset =
      voting
      |> Voting.changeset(%{})
      |> Ecto.Changeset.put_assoc(:halls, halls)

    case Repo.update(voting_changeset) do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  def delete_halls_votings(%Voting{id: voting_id}) do
    Repo.delete_all(from h in HallVoting, where: h.voting_id == ^voting_id)
  end
end
