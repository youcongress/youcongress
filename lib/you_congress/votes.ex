defmodule YouCongress.Votes do
  @moduledoc """
  The Votes context.
  """

  import Ecto.Query, warn: false

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

  def list_votes(opts) when is_list(opts) do
    preload_tables = Keyword.get(opts, :preload, [])

    base_query =
      from(v in Vote,
        join: a in assoc(v, :author),
        left_join: o in assoc(v, :opinion),
        select: v
      )

    Enum.reduce(
      opts,
      base_query,
      fn
        {:author_ids, author_ids}, query ->
          where(query, [v], v.author_id in ^author_ids)

        {:voting_ids, voting_ids}, query ->
          where(query, [v], v.voting_id in ^voting_ids)

        {:twin, twin}, query ->
          where(query, [v], v.twin == ^twin)

        {:direct, direct}, query ->
          where(query, [v], v.direct == ^direct)

        {:without_opinion, without_opinion}, query ->
          where(query, [v], is_nil(v.opinion_id) == ^without_opinion)

        {:order_by, order_by}, query ->
          order_by(query, ^order_by)

        {:order_by_strong_opinions_first, true}, query ->
          from [v, _a, o] in query,
            order_by: [
              desc:
                fragment(
                  "CASE
                  WHEN ? = true THEN 1
                  ELSE 0
                  END",
                  v.direct
                ),
              desc:
                fragment(
                  "CASE
                  WHEN ? IS NULL THEN 0
                  ELSE 1
                  END",
                  v.opinion_id
                ),
              desc:
                fragment(
                  "CASE
                  WHEN ? IS NULL THEN 0
                  ELSE 1
                  END",
                  o.source_url
                ),
              desc: o.likes_count,
              desc: o.descendants_count,
              desc:
                  v.answer
            ]

        {:limit, limit}, query ->
          limit(query, ^limit)

        {:offset, offset}, query ->
          offset(query, ^offset)

        _, query ->
          query
      end
    )
    |> preload(^preload_tables)
    |> Repo.all()
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
    twin_options = Keyword.get(opts, :twin_options, [true, false])
    source_filter = Keyword.get(opts, :source_filter)
    answer = Keyword.get(opts, :answer)

    base_query =
      Vote
      |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
      |> join(:inner, [v, a], o in YouCongress.Opinions.Opinion, on: v.opinion_id == o.id)
      |> where(
        [v, a, o],
        v.voting_id == ^voting_id and not is_nil(v.opinion_id) and
          v.id not in ^exclude_ids and
          v.twin in ^twin_options
      )

    query =
      case source_filter do
        :quotes -> where(base_query, [v, a, o], not is_nil(o.source_url))
        :users -> where(base_query, [v, a, o], is_nil(o.source_url))
        _ -> base_query
      end

    query =
      if answer do
        query
        |> where([v, a, o], v.answer == ^answer)
      else
        query
      end

    query
    |> order_by([v, a, o], [
      {:desc, o.likes_count},
      fragment("? DESC", o.descendants_count),
      fragment("CASE
            WHEN ? IS NOT NULL THEN 1
            WHEN ? IS NOT NULL THEN 2
            WHEN ? = FALSE THEN 3
            ELSE 4
          END", o.source_url, a.wikipedia_url, o.twin),
      {:desc, o.updated_at}
    ])
    |> preload(^include_tables)
    |> Repo.all()
  end

  @doc """
  Returns the list of votes for a voting without opinion.
  """
  @spec list_votes_without_opinion(integer, Keyword.t()) :: [Vote.t(), ...]
  def list_votes_without_opinion(voting_id, opts \\ []) do
    include_tables = Keyword.get(opts, :include, [])
    exclude_ids = Keyword.get(opts, :exclude_ids, [])
    twin_options = Keyword.get(opts, :twin_options, [true, false])
    answer_filter = Keyword.get(opts, :answer_filter)

    base_query =
      Vote
      |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
      |> where(
        [v, a],
        v.voting_id == ^voting_id and is_nil(v.opinion_id) and v.id not in ^exclude_ids and
          v.twin in ^twin_options
      )

    query =
      if answer_filter do
        base_query
        |> where([v, a], v.answer == ^answer_filter)
      else
        base_query
      end

    query
    |> preload(^include_tables)
    |> Repo.all()
  end

  def list_votes_by_author_id(author_id, opts \\ []) do
    tables = Keyword.get(opts, :preload, [])

    Vote
    |> where([v], v.author_id == ^author_id)
    |> preload(^tables)
    |> order_by(
      [v],
      fragment(
        "CASE
      WHEN ? IS NOT NULL AND ? = FALSE THEN 0
      WHEN ? IS NOT NULL AND ? = FALSE THEN 1
      WHEN ? = TRUE THEN 2
      ELSE 3
    END",
        # Conditions for the first WHEN (votes with non-AI opinion)
        v.opinion_id,
        v.twin,
        # Conditions for the second WHEN (votes with AI opinion)
        v.opinion_id,
        v.twin,
        # Conditions for the third WHEN (direct votes without opinion)
        v.direct
        # Else (delegated votes without opinion)
      )
    )
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

  def get_vote(id) do
    Repo.get(Vote, id)
  end

  def get_vote(id, preload: preload) do
    Vote
    |> Repo.get(id)
    |> Repo.preload(preload)
  end

  @doc """
  Gets a single vote by some options.

  ## Examples

      iex> get_by(%{id: 123})
      %Vote{}

      iex> get_by(%{id: 456})
      nil
  """
  @spec get_by(map) :: Vote.t() | nil
  def get_by(options) do
    Repo.get_by(Vote, options)
  end

  @doc """
  Gets a single vote by some options and preload some tables.
  """
  @spec get_by(Keyword.t(), Keyword.t()) :: Vote.t() | nil
  def get_by(options, preload: tables) do
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
  Updates the author_id for all votes associated with a given opinion.

  This is used when an opinion's author is changed, to ensure votes
  remain associated with the correct author.

  ## Examples

      iex> update_author_for_opinion_votes(123, 456)
      {2, nil}

  """
  def update_author_for_opinion_votes(opinion_id, new_author_id) do
    query =
      from v in Vote,
        where: v.opinion_id == ^opinion_id

    Repo.update_all(query, set: [author_id: new_author_id])
  end

  @doc """
  Creates, updates or deletes a vote.
  """
  @spec create_or_update(map) :: {:ok, Vote.t()} | {:ok, :deleted} | {:error, String.t()}
  def create_or_update(%{voting_id: voting_id, author_id: author_id} = attrs) do
    case Repo.get_by(Vote, %{voting_id: voting_id, author_id: author_id}) do
      nil -> create_vote(attrs)
      vote -> update_vote(vote, attrs)
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

  def count_by_voting(voting_id) do
    from(v in Vote,
      where: v.voting_id == ^voting_id,
      select: count(v.id)
    )
    |> Repo.one()
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

  Example:
  > count_by_response(1)
  [{"for", 4}, {"against", 2}, {"abstain", 6}]
  """
  def count_by_response(_voting_id, opts \\ []) do
    has_opinion_id = Keyword.get(opts, :has_opinion_id, nil)
    twin = Keyword.get(opts, :twin)

    query =
      from(v in Vote,
        group_by: v.answer,
        select: {v.answer, count(v.answer)}
      )

    query =
      if has_opinion_id do
        from(v in query, where: not is_nil(v.opinion_id))
      else
        query
      end

    query =
      if is_nil(twin) do
        query
      else
        from(v in query, where: v.twin == ^twin)
      end

    query
    |> Repo.all()
  end

  def count_by_response_map(voting_id, opts \\ []) do
    count_by_response(voting_id, opts)
    |> Enum.into(%{})
  end

  def count_with_opinion_source(voting_id, opts \\ []) do
    source_filter = Keyword.get(opts, :source_filter)
    answer = Keyword.get(opts, :answer)

    base_query =
      from v in Vote,
        join: o in YouCongress.Opinions.Opinion,
        on: v.opinion_id == o.id,
        where: v.voting_id == ^voting_id and not is_nil(v.opinion_id),
        select: count(v.id)

    query =
      case source_filter do
        :quotes -> from [v, o] in base_query, where: not is_nil(o.source_url)
        :users -> from [v, o] in base_query, where: is_nil(o.source_url)
        _ -> base_query
      end

    query =
      if answer do
        from [v, o] in query, where: v.answer == ^answer
      else
        query
      end

    Repo.one(query)
  end

  def count_by_response_map_by_source(voting_id, opts \\ []) do
    source_filter = Keyword.get(opts, :source_filter)

    base_query =
      from v in Vote,
        join: o in YouCongress.Opinions.Opinion,
        on: v.opinion_id == o.id,
        where: v.voting_id == ^voting_id and not is_nil(v.opinion_id),
        group_by: v.answer,
        select: {v.answer, count(v.answer)}

    query =
      case source_filter do
        :quotes -> from [v, o] in base_query, where: not is_nil(o.source_url)
        :users -> from [v, o] in base_query, where: is_nil(o.source_url)
        _ -> base_query
      end

    query
    |> Repo.all()
    |> Enum.into(%{})
  end

  def count_by(opts) when is_list(opts) do
    base_query = from(v in Vote, select: count(v.id))

    Enum.reduce(
      opts,
      base_query,
      fn
        {:voting_id, voting_id}, query ->
          where(query, [v], v.voting_id == ^voting_id)

        {:twin, twin}, query ->
          where(query, [v], v.twin == ^twin)

        {:direct, direct}, query ->
          where(query, [v], v.direct == ^direct)

        {:has_opinion_id, has_opinion_id}, query ->
          if has_opinion_id do
            where(query, [v], not is_nil(v.opinion_id))
          else
            where(query, [v], is_nil(v.opinion_id))
          end

        {:answer, answer}, query ->
          where(query, [v], v.answer == ^answer)

        _, query ->
          query
      end
    )
    |> Repo.one()
  end

  def get_current_user_vote(voting_id, author_id) do
    Vote
    |> join(:inner, [v], a in YouCongress.Authors.Author, on: v.author_id == a.id)
    |> where(
      [v, a],
      v.voting_id == ^voting_id and v.author_id == ^author_id
    )
    |> preload([:opinion])
    |> Repo.one()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking vote changes.

  ## Examples

      iex> change_vote(vote)
      %Ecto.Changeset{data: %Vote{}}

  """
  def public?(%Vote{} = _vote) do
    true
  end
end
