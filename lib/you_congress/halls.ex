defmodule YouCongress.Halls do
  @moduledoc """
  The Halls context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Halls.Hall

  @doc """
  Returns the list of halls.

  ## Examples

      iex> list_halls()
      [%Hall{}, ...]

  """
  def list_halls(opts \\ []) do
    base_query = from(h in Hall)

    Enum.reduce(opts, base_query, fn
      {:name_contains, txt}, query ->
        txt = String.replace(txt, " ", "-")
        from h in query, where: ilike(h.name, ^"%#{txt}%")

      {:search, search}, query ->
        terms = YouCongress.SearchParser.parse(search)

        Enum.reduce(terms, query, fn term, query_acc ->
          term_slug = String.replace(term, " ", "-")
          from h in query_acc, where: ilike(h.name, ^"%#{term_slug}%")
        end)

      _, query ->
        query
    end)
    |> Repo.all()
  end

  @doc """
  Gets a single hall.

  Raises `Ecto.NoResultsError` if the Hall does not exist.

  ## Examples

      iex> get_hall!(123)
      %Hall{}

      iex> get_hall!(456)
      ** (Ecto.NoResultsError)

  """
  def get_hall!(id), do: Repo.get!(Hall, id)

  @doc """
  Fetches a hall by its name

  ## Examples
      iex> get_by_name("Somename")
      %Hall{name: "Somename"}

      iex> get_by_name("NonExistentname")
      nil
  """
  @spec get_by_name(binary) :: Hall.t() | nil
  def get_by_name(name) do
    Repo.get_by(Hall, name: name)
  end

  @spec get_by_name(binary, list) :: Hall.t() | nil
  def get_by_name(name, preload: tables) do
    hall = Repo.get_by(Hall, name: name)
    hall && Repo.preload(hall, tables)
  end

  @doc """
  Gets a hall by its name. If it doesn't exist, creates a new hall with the given name.

  ## Examples

      iex> get_or_create_by_name("Somename")
      {:ok, %Hall{name: "Somename"}}

      iex> get_or_create_by_name("Existingname")
      {:ok, %Hall{name: "Existingname"}}

  """
  @spec get_or_create_by_name(binary) :: {:ok, Hall.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_by_name(name) when is_binary(name) do
    case get_by_name(name) do
      nil -> create_hall(%{name: name})
      hall -> {:ok, hall}
    end
  end

  def list_or_create_by_names(names) do
    halls = Enum.map(names, &get_or_create_by_name/1)

    if Enum.all?(halls, &(elem(&1, 0) == :ok)) do
      {:ok, Enum.map(halls, &elem(&1, 1))}
    else
      :error
    end
  end

  @doc """
  Gets a list of halls by their names.

  ## Examples

      iex> get_halls_by_names(["hall1", "hall2"])
      [%Hall{name: "hall1"}, %Hall{name: "hall2"}]
  """
  @spec get_halls_by_names([binary()]) :: [Hall.t()]
  def get_halls_by_names(names) when is_list(names) do
    Repo.all(from h in Hall, where: h.name in ^names)
  end

  def get_halls_by_names(_), do: []

  @doc """
  Creates a hall.

  ## Examples

      iex> create_hall(%{field: value})
      {:ok, %Hall{}}

      iex> create_hall(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_hall(attrs \\ %{}) do
    %Hall{}
    |> Hall.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a hall.

  ## Examples

      iex> update_hall(hall, %{field: new_value})
      {:ok, %Hall{}}

      iex> update_hall(hall, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_hall(%Hall{} = hall, attrs) do
    hall
    |> Hall.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a hall.

  ## Examples

      iex> delete_hall(hall)
      {:ok, %Hall{}}

      iex> delete_hall(hall)
      {:error, %Ecto.Changeset{}}

  """
  def delete_hall(%Hall{} = hall) do
    Repo.delete(hall)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking hall changes.

  ## Examples

      iex> change_hall(hall)
      %Ecto.Changeset{data: %Hall{}}

  """
  def change_hall(%Hall{} = hall, attrs \\ %{}) do
    Hall.changeset(hall, attrs)
  end

  def classify(text, model \\ :"gpt-5-nano") do
    classifier_impl().classify(text, model)
  end

  def classify!(text, model \\ :"gpt-5-nano") do
    {:ok, %{main_tag: main_tag, other_tags: other_tags}} = classifier_impl().classify(text, model)
    %{main_tag: main_tag, other_tags: other_tags}
  end

  @doc """
  Returns halls that have pending quotes (unverified quotes with source URLs).
  """
  def list_halls_with_pending_quotes do
    import Ecto.Query, warn: false

    from(h in Hall,
      join: hv in "halls_statements",
      on: hv.hall_id == h.id,
      join: v in "statements",
      on: hv.statement_id == v.id,
      join: ov in "opinions_statements",
      on: ov.statement_id == v.id,
      join: o in "opinions",
      on: ov.opinion_id == o.id,
      where: not is_nil(o.source_url) and is_nil(o.verified_at),
      distinct: h.id,
      order_by: h.name
    )
    |> Repo.all()
  end

  defp classifier_impl do
    Application.get_env(:you_congress, :hall_classifier, YouCongress.Halls.Classification)
  end
end
