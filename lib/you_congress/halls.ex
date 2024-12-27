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
  def list_halls do
    Repo.all(Hall)
  end

  def list_halls(name_contains: txt) do
    txt = String.replace(txt, " ", "-")
    Repo.all(from(h in Hall, where: ilike(h.name, ^"%#{txt}%")))
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

  def classify(text, model \\ :"gpt-4o") do
    classifier_impl().classify(text, model)
  end

  def classify!(text, model \\ :"gpt-4o") do
    {:ok, %{tags: tags}} = classifier_impl().classify(text, model)
    tags
  end

  defp classifier_impl do
    Application.get_env(:you_congress, :hall_classifier, YouCongress.Halls.Classification)
  end
end
