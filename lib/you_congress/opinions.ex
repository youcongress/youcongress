defmodule YouCongress.Opinions do
  @moduledoc """
  The Opinions context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Opinions.Opinion

  @doc """
  Returns the list of opinions.

  ## Examples

      iex> list_opinions()
      [%Opinion{}, ...]

  """
  def list_opinions(opts \\ []) do
    query = build_query(opts)
    Repo.all(query)
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

  def get_opinion!(id, preload: tables) do
    Repo.get!(Opinion, id)
    |> Repo.preload(tables)
  end

  def get_opinion(nil), do: nil
  def get_opinion(id), do: Repo.get(Opinion, id)

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

  def exists?(opts) do
    query = build_query(opts)
    Repo.exists?(query)
  end

  defp build_query(opts) do
    base_query = from(o in Opinion)

    Enum.reduce(opts, base_query, fn
      {:initial_ancestry, ancestry}, query ->
        from q in query, where: fragment("? LIKE ?", q.ancestry, ^"#{ancestry}/%")

      {:ancestry, ancestry}, query ->
        from q in query, where: q.ancestry == ^"#{ancestry}"

      {:twin, twin_value}, query ->
        from q in query, where: q.twin == ^twin_value

      {:preload, preloads}, query ->
        from q in query, preload: ^preloads

      {:order_by, order}, query ->
        from q in query, order_by: ^order

      {:limit, limit}, query ->
        from q in query, limit: ^limit

      {:offset, offset}, query ->
        from q in query, offset: ^offset

      {key, value}, query when is_atom(key) ->
        from q in query, where: field(q, ^key) == ^value

      _, query ->
        query
    end)
  end

  def delete_opinion_and_descendants(%Opinion{} = opinion) do
    subtree_ids = Opinion.subtree_ids(opinion)
    Repo.delete_all(from o in Opinion, where: o.id in ^subtree_ids)
  end
end
