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

      iex> list_votings(order_by: [desc: :id])
      [%Voting{}, ...]

  """
  def list_votings(order_by: order_by) do
    Repo.all(from v in Voting, order_by: ^order_by)
  end

  def list_random_votings(except_id, limit) do
    Repo.all(from v in Voting, where: v.id != ^except_id, limit: ^limit)
  end

  @doc """
  Gets a voting given some params.

  ## Examples

      iex> get_voting!(%{title: "Yey"})
      %Voting{}

      iex> get_voting!(33)
      %Voting{}
  """
  @spec get_voting!(%{} | integer) :: Voting.t()
  def get_voting!(options) when is_map(options) do
    Repo.get_by!(Voting, options)
  end

  def get_voting!(id), do: Repo.get!(Voting, id)

  @doc """
  Gets a single voting with a table preloaded such as votes and authors.

  Raises `Ecto.NoResultsError` if the Voting does not exist.

  ## Examples

      iex> get_voting!(123, include: [:votes])
      %Voting{}
  """
  def get_voting!(id, include: tables) do
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
    voting
    |> Voting.changeset(attrs)
    |> Repo.update()
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

  def get_voting_by_slug(slug) do
    Repo.get_by(Voting, slug: slug)
  end

  def get_voting_by_slug!(slug) do
    Repo.get_by!(Voting, slug: slug)
  end

  def regenerate_slug(voting) do
    voting
    |> Voting.changeset(%{slug: nil})
    |> Repo.update()
  end
end
