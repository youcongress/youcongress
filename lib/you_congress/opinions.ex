defmodule YouCongress.Opinions do
  @moduledoc """
  The Opinions context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo

  @doc """
  Returns the list of opinions.

  ## Examples

      iex> list_opinions()
      [%Opinion{}, ...]

  """
  def list_opinions do
    Repo.all(Opinion)
  end

  @doc """
  Returns the list of opinions for a voting.

  ## Examples

        iex> list_opinions("Nuclear Energy")
        [%Opinion{}, ...]

  """
  def list_opinions(voting_id) do
    Repo.all(Opinion, where: [voting_id: voting_id])
  end

  @doc """
  Gets a single opinion.

  Raises `Ecto.NoResultsError` if the Opinion does not exist.

  ## Examples

      iex> get_opinion!(123)
      %Opinion{}

      iex> get_opinion!(456)
      ** (Ecto.NoResultsError)

  """
  def get_opinion!(id), do: Repo.get!(Opinion, id)

  @doc """
  Creates a opinion.

  ## Examples

      iex> create_opinion(%{field: value})
      {:ok, %Opinion{}}

      iex> create_opinion(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_opinion(attrs \\ %{}) do
    %Opinion{}
    |> Opinion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a opinion.

  ## Examples

      iex> update_opinion(opinion, %{field: new_value})
      {:ok, %Opinion{}}

      iex> update_opinion(opinion, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_opinion(%Opinion{} = opinion, attrs) do
    opinion
    |> Opinion.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a opinion.

  ## Examples

      iex> delete_opinion(opinion)
      {:ok, %Opinion{}}

      iex> delete_opinion(opinion)
      {:error, %Ecto.Changeset{}}

  """
  def delete_opinion(%Opinion{} = opinion) do
    Repo.delete(opinion)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking opinion changes.

  ## Examples

      iex> change_opinion(opinion)
      %Ecto.Changeset{data: %Opinion{}}

  """
  def change_opinion(%Opinion{} = opinion, attrs \\ %{}) do
    Opinion.changeset(opinion, attrs)
  end
end
