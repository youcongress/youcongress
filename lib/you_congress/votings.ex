defmodule YouCongress.Votings do
  @moduledoc """
  The Votings context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votings.Voting
  alias YouCongress.HallsVotings
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Workers.VotingHallsGeneratorWorker

  @doc """
  Returns the list of votings.

  ## Examples

      iex> list_votings()
      [%Voting{}, ...]

  """
  def list_votings do
    Repo.all(Voting)
  end

  @doc """
  Returns the list of votings ordered by `order_by`.

  ## Examples

      iex> list_votings(order: desc)
      [%Voting{}, ...]

  """
  def list_votings(opts) do
    preload = opts[:preload] || []

    base_query = from(v in Voting)
    base_query = maybe_include_two_opinions(base_query, opts[:include_two_opinions] || false)

    query =
      Enum.reduce(
        opts,
        base_query,
        fn
          {:hall_name, hall_name}, query ->
            from(v in query,
              join: h in assoc(v, :halls),
              where: h.name == ^hall_name,
              distinct: true
            )

          {:title_contains, title}, query ->
            where(query, [v], ilike(v.title, ^"%#{title}%"))

          {:order, :updated_at_desc}, query ->
            order_by(query, desc: :updated_at)

          {:order, :opinion_likes_count_desc}, query ->
            order_by(query, desc: :opinion_likes_count, desc: :inserted_at)

          {:order, :inserted_at_desc}, query ->
            order_by(query, desc: :inserted_at)

          {:order, :desc}, query ->
            order_by(query, desc: :updated_at)

          {:order, :random}, query ->
            order_by(query, fragment("RANDOM()"))

          {:limit, limit}, query ->
            limit(query, ^limit)

          {:offset, offset}, query ->
            offset(query, ^offset)

          _, query ->
            query
        end
      )

    query
    |> Repo.all()
    |> Repo.preload(preload)
  end

  defp maybe_include_two_opinions(query, false), do: query

  defp maybe_include_two_opinions(base_query, true) do
    top_votes_query =
      from v in YouCongress.Votes.Vote,
        join: o in assoc(v, :opinion),
        where: is_nil(o.ancestry),
        select: %{
          id: v.id,
          voting_id: v.voting_id,
          rank:
            over(
              row_number(),
              partition_by: o.voting_id,
              order_by: [
                asc: fragment("CASE WHEN ? IS NOT NULL THEN 0 ELSE 1 END", o.source_url),
                desc: o.likes_count,
                desc: o.id
              ]
            )
        }

    filtered_votes =
      from v in YouCongress.Votes.Vote,
        join: ranked in subquery(top_votes_query),
        on: v.id == ranked.id and ranked.rank <= 2,
        preload: [opinion: :author, answer: []]

    from v in base_query,
      preload: [votes: ^filtered_votes]
  end

  def list_random_votings(except_id, limit) do
    Repo.all(
      from v in Voting,
        where: v.id != ^except_id,
        order_by: fragment("RANDOM()"),
        limit: ^limit
    )
  end

  @doc """
  Gets a voting given some params.

  ## Examples

      iex> get_voting!(%{title: "Yey"})
      %Voting{}

      iex> get_voting!(33)
      %Voting{}
  """
  @spec get_voting!(list | integer) :: Voting.t()
  def get_voting!(options) when is_list(options) do
    Repo.get_by!(Voting, options)
  end

  def get_voting!(id), do: Repo.get!(Voting, id)

  def get_voting(id) do
    Repo.get(Voting, id)
  end

  @doc """
  Gets a single voting with a table preloaded such as votes and authors.

  Raises `Ecto.NoResultsError` if the Voting does not exist.

  ## Examples

      iex> get_voting!(123, preload: [:votes])
      %Voting{}
  """
  def get_voting!(id, preload: tables) do
    Repo.get!(Voting, id) |> Repo.preload(tables)
  end

  @doc """
  Creates a voting.

  ## Examples

      iex> create_voting(%{field: value})
      {:ok, %Voting{}}

      iex> create_voting(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_voting(attrs \\ %{}) do
    voting_changeset = Voting.changeset(%Voting{}, attrs)

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:voting, voting_changeset)
      |> Oban.insert(:job, fn %{voting: voting} ->
        VotingHallsGeneratorWorker.new(%{voting_id: voting.id})
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{voting: voting}} -> {:ok, voting}
      {:error, :voting, error, _} -> {:error, error}
      {:error, _, _, _} -> {:error, %Ecto.Changeset{}}
    end
  end

  @doc """
  Updates a voting.

  ## Examples

      iex> update_voting(voting, %{field: new_value})
      {:ok, %Voting{}}

      iex> update_voting(voting, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_voting(%Voting{} = voting, attrs) do
    result =
      voting
      |> Voting.changeset(attrs)
      |> Repo.update()

    with {:ok, new_voting} <- result do
      if attrs[:title] && attrs[:title] != voting.title do
        # Only admins can update voting so it's ok to:
        # 1. do it synchronously
        # 2. raise an error if it fails
        HallsVotings.sync!(new_voting.id)
      end

      {:ok, new_voting}
    end
  end

  @doc """
  Deletes a voting.

  ## Examples

      iex> delete_voting(voting)
      {:ok, %Voting{}}

      iex> delete_voting(voting)
      {:error, %Ecto.Changeset{}}

  """
  def delete_voting(%Voting{} = voting) do
    YouCongress.HallsVotings.delete_halls_votings(voting)
    Repo.delete(voting)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking voting changes.

  ## Examples

      iex> change_voting(voting)
      %Ecto.Changeset{data: %Voting{}}

  """
  def change_voting(%Voting{} = voting, attrs \\ %{}) do
    Voting.changeset(voting, attrs)
  end

  @doc """
  Returns the number of votings.

  ## Examples

      > count()
      42

  """
  def count do
    Repo.aggregate(Voting, :count, :id)
  end

  @doc """
  Returns the voting with the given slug.
  """

  def get_by(opts) do
    Repo.get_by(Voting, opts)
  end

  def get_by!(opts) do
    Repo.get_by!(Voting, opts)
  end

  def regenerate_slug(voting) do
    voting
    |> Voting.changeset(%{slug: nil})
    |> Repo.update()
  end

  def regenerate_all_voting_slugs do
    Repo.all(Voting)
    |> Enum.each(&regenerate_slug/1)
  end

  def sync_opinion_likes_count(voting) do
    count =
      from(o in Opinion,
        where: o.voting_id == ^voting.id and is_nil(o.ancestry),
        select: coalesce(sum(o.likes_count), 0)
      )
      |> Repo.one() || 0

    update_voting(voting, %{opinion_likes_count: count})
  end

  def votings_count_created_in_the_last_hour do
    from(v in Voting, where: v.inserted_at > ago(1, "hour"), select: count(v.id))
    |> Repo.one()
  end
end
