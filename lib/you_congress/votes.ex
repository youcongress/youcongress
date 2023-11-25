defmodule YouCongress.Votes do
  @moduledoc """
  The Votes context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Repo
  alias YouCongress.Votes.Vote

  @doc """
  Returns the list of votes.

  ## Examples

      iex> list_votes()
      [%Vote{}, ...]

  """
  def list_votes do
    Repo.all(Vote)
  end

  @doc """
  Returns the list of votes for a voting.

  ## Examples

        iex> list_votes("Nuclear Energy")
        [%Vote{}, ...]

  """
  def list_votes(voting_id) do
    Repo.all(Vote, where: [voting_id: voting_id])
  end

  @doc """
  Gets a single vote.

  Raises `Ecto.NoResultsError` if the Vote does not exist.

  ## Examples

      iex> get_vote!(123)
      %Vote{}

      iex> get_vote!(456)
      ** (Ecto.NoResultsError)

  """
  def get_vote!(id), do: Repo.get!(Vote, id)

  @doc """
  Creates a vote.

  ## Examples

      iex> create_vote(%{field: value})
      {:ok, %Vote{}}

      iex> create_vote(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_vote(attrs \\ %{}) do
    %Vote{}
    |> Vote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a vote.

  ## Examples

      iex> update_vote(vote, %{field: new_value})
      {:ok, %Vote{}}

      iex> update_vote(vote, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_vote(%Vote{} = vote, attrs) do
    vote
    |> Vote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates, updates or deletes a vote.
  """
  @spec next_vote(map) :: {:ok, %Vote{}} | {:ok, :deleted} | {:error, String.t()}
  def next_vote(attrs) do
    case Repo.get_by(Vote, %{voting_id: attrs[:voting_id], author_id: attrs[:author_id]}) do
      nil ->
        create_vote(attrs)

      vote ->
        if vote.answer_id == attrs[:answer_id] do
          case delete_vote(vote) do
            {:ok, _} ->
              {:ok, :deleted}

            {:error, _} ->
              {:error, "Error deleting vote"}
          end
        else
          update_vote(vote, attrs)
        end
    end
  end

  @doc """
  Deletes a vote.

  ## Examples

      iex> delete_vote(vote)
      {:ok, %Vote{}}

      iex> delete_vote(vote)
      {:error, %Ecto.Changeset{}}

  """
  def delete_vote(%Vote{} = vote) do
    Repo.delete(vote)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vote changes.

  ## Examples

      iex> change_vote(vote)
      %Ecto.Changeset{data: %Vote{}}

  """
  def change_vote(%Vote{} = vote, attrs \\ %{}) do
    Vote.changeset(vote, attrs)
  end

  @doc """
  Returns the number of votes.
  """
  @spec count() :: integer()
  def count do
    Repo.aggregate(Vote, :count, :id)
  end

  @doc """
  Returns the number of votes of an author.
  """
  @spec count(list) :: integer()
  def count(author_id: author_id) do
    Repo.aggregate(Vote, :count, :id, where: [author_id: author_id])
  end
end
