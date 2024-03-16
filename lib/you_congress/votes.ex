defmodule YouCongress.Votes do
  @moduledoc """
  The Votes context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.DelegationVotes
  alias YouCongress.Votes.Vote
  alias YouCongress.Repo

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
  @spec list_votes(integer, Keyword.t() | nil) :: [Vote.t(), ...]
  def list_votes(voting_id, opts \\ []) do
    include_tables = Keyword.get(opts, :include, [])

    Vote
    |> where([v], v.voting_id == ^voting_id)
    |> preload(^include_tables)
    |> Repo.all()
  end

  @doc """
  Returns the list of votes for a voting with opinion.
  """
  @spec list_votes_with_opinion(integer, Keyword.t()) :: [Vote.t(), ...]
  def list_votes_with_opinion(voting_id, opts \\ []) do
    include_tables = Keyword.get(opts, :include, [])
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    Vote
    |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
    |> where(
      [v, a],
      v.voting_id == ^voting_id and not is_nil(v.opinion) and
        v.id not in ^exclude_ids
    )
    |> preload(^include_tables)
    |> Repo.all()
  end

  def get_current_user_vote(voting_id, author_id) do
    Vote
    |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
    |> where(
      [v, a],
      v.voting_id == ^voting_id and v.author_id == ^author_id
    )
    |> preload(:answer)
    |> Repo.one()
  end

  @doc """
  Returns the list of votes for a voting without opinion.
  """
  @spec list_votes_without_opinion(integer, Keyword.t()) :: [Vote.t(), ...]
  def list_votes_without_opinion(voting_id, opts \\ []) do
    include_tables = Keyword.get(opts, :include, [])
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    Vote
    |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
    |> where(
      [v, a],
      v.voting_id == ^voting_id and is_nil(v.opinion) and v.id not in ^exclude_ids
    )
    |> preload(^include_tables)
    |> Repo.all()
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
  Gets a single vote by some options.
  """
  @spec get_vote(map) :: Vote.t() | nil
  def get_vote(options) do
    Repo.get_by(Vote, options)
  end

  @doc """
  Gets a single vote by some options and preload some tables.
  """
  @spec get_vote(Keyword.t(), Keyword.t()) :: Vote.t() | nil
  def get_vote(options, preload: tables) do
    Vote
    |> Repo.get_by(options)
    |> Repo.preload(tables)
  end

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
  @spec next_vote(map) :: {:ok, Vote.t()} | {:ok, :deleted} | {:error, String.t()}
  def next_vote(%{voting_id: voting_id, author_id: author_id} = attrs) do
    case Repo.get_by(Vote, %{voting_id: voting_id, author_id: author_id}) do
      nil -> create_vote(attrs)
      vote -> delete_or_update_vote(vote, voting_id, author_id, attrs)
    end
  end

  @spec delete_or_update_vote(Vote.t(), integer, integer, map) ::
          {:ok, Vote.t()} | {:ok, :deleted} | {:error, String.t()}
  defp delete_or_update_vote(%Vote{} = vote, voting_id, author_id, attrs) do
    if vote.answer_id == attrs[:answer_id] && vote.direct do
      case delete_vote(vote) do
        {:ok, _} ->
          DelegationVotes.update_author_voting_delegated_votes(%{
            author_id: author_id,
            voting_id: voting_id
          })

          {:ok, :deleted}

        {:error, _} ->
          {:error, "Error deleting vote"}
      end
    else
      attrs = Map.put(attrs, :direct, true)
      update_vote(vote, attrs)
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

  def delete_vote(%{voting_id: voting_id, author_id: author_id}) do
    from(v in Vote,
      where: v.voting_id == ^voting_id and v.author_id == ^author_id
    )
    |> Repo.delete_all()
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
  @spec count_by_author_id(integer | nil) :: integer() | nil
  def count_by_author_id(nil), do: nil

  def count_by_author_id(author_id) do
    from(v in Vote,
      where: v.author_id == ^author_id,
      select: count(v.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns the number of votes of a voting.
  """
  def count_by_response(voting_id) do
    from(v in Vote,
      join: a in assoc(v, :answer),
      where: v.voting_id == ^voting_id,
      group_by: a.response,
      select: {a.response, count(a.response)}
    )
    |> Repo.all()
  end

  def public?(%Vote{} = vote) do
    vote.answer_id not in YouCongress.Votes.Answers.private_ids()
  end
end
