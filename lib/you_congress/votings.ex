defmodule YouCongress.Votings do
  @moduledoc """
  The Votings context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votings.Voting

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
    base_query = from v in Voting, preload: ^preload
    opts = replace_hall_name_with_ids(opts, opts[:hall_name])

    Enum.reduce(
      opts,
      base_query,
      fn
        {:title_contains, title}, query ->
          where(query, [v], fragment("? ILIKE ?", v.title, ^"%#{title}%"))

        {:order, :updated_at_desc}, query ->
          order_by(query, desc: :updated_at)

        {:order, :inserted_at_desc}, query ->
          order_by(query, desc: :inserted_at)

        {:order, :desc}, query ->
          order_by(query, desc: :updated_at)

        {:order, :random}, query ->
          order_by(query, fragment("RANDOM()"))

        {:ids, ids}, query ->
          where(query, [voting], voting.id in ^ids)

        _, query ->
          query
      end
    )
    |> Repo.all()
  end

  @spec replace_hall_name_with_ids(list, binary | nil) :: list
  defp replace_hall_name_with_ids(opts, nil), do: opts

  defp replace_hall_name_with_ids(opts, hall_name) do
    case YouCongress.Halls.get_by_name(hall_name, preload: :votings) do
      nil ->
        opts

      hall ->
        voting_ids = Enum.map(hall.votings, & &1.id)

        opts
        |> Keyword.delete(:hall_name)
        |> Keyword.put(:ids, voting_ids)
    end
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
    %Voting{}
    |> Voting.changeset(attrs)
    |> Repo.insert()
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
    case voting
         |> Voting.changeset(attrs)
         |> Repo.update() do
      {:ok, new_voting} ->
        if attrs[:title] && attrs[:title] != voting.title do
          YouCongress.HallsVotings.sync!(new_voting.id)
        end

        {:ok, new_voting}

      {:error, changeset} ->
        {:error, changeset}
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
end
