defmodule YouCongress.Authors do
  @moduledoc """
  The Authors context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Authors.Author

  @doc """
  Returns the list of authors.

  ## Examples

      iex> list_authors()
      [%Author{}, ...]

  """
  def list_authors do
    Repo.all(Author)
  end

  @doc """
  Gets a single author.

  Raises `Ecto.NoResultsError` if the Author does not exist.

  ## Examples

      iex> get_author!(123)
      %Author{}

      iex> get_author!(456)
      ** (Ecto.NoResultsError)

  """
  def get_author!(id), do: Repo.get!(Author, id)

  @doc """
  Creates a author.

  ## Examples

      iex> create_author(%{field: value})
      {:ok, %Author{}}

      iex> create_author(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_author(attrs \\ %{}) do
    %Author{}
    |> Author.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds a author by name or creates a new one.

  ## Examples

      iex> find_by_name_or_create("John Doe")
      {:ok, %Author{}}

      iex> find_by_name_or_create("John Doe")
      {:error, %Ecto.Changeset{}}

  """
  def find_by_name_or_create(%{"name" => name} = author_data) do
    case find_by(:name, name) do
      nil -> create_author(author_data)
      author -> {:ok, author}
    end
  end

  @doc """
  Finds a author by wikipedia url or creates a new one.

  ## Examples

      iex> find_by_wikipedia_url_or_create("https://en.wikipedia.org/wiki/John_Doe")
      {:ok, %Author{}}

      iex> find_by_wikipedia_url_or_create("https://en.wikipedia.org/wiki/John_Doe")
      {:error, %Ecto.Changeset{}}

  """
  def find_by_wikipedia_url_or_create(%{"wikipedia_url" => wikipedia_url} = author_data) do
    case find_by(:wikipedia_url, wikipedia_url) do
      nil -> create_author(author_data)
      author -> {:ok, author}
    end
  end

  @doc """
  Finds an author by column and name.

  ## Examples

      iex> find_by(:name, "John Doe")
      %Author{}

      iex> find_by(:name, "John Doe")
      nil

      iex> find_by(:wikipedia_url, "https://en.wikipedia.org/wiki/John_Doe")
      %Author{}

      iex> find_by(:wikipedia_url, "https://en.wikipedia.org/wiki/John_Doe")
      nil

  """
  def find_by(column, name) when column in [:name, :wikipedia_url] do
    Repo.get_by(Author, [{column, name}])
  end

  @doc """
  Updates a author.

  ## Examples

      iex> update_author(author, %{field: new_value})
      {:ok, %Author{}}

      iex> update_author(author, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_author(%Author{} = author, attrs) do
    author
    |> Author.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a author.

  ## Examples

      iex> delete_author(author)
      {:ok, %Author{}}

      iex> delete_author(author)
      {:error, %Ecto.Changeset{}}

  """
  def delete_author(%Author{} = author) do
    Repo.delete(author)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking author changes.

  ## Examples

      iex> change_author(author)
      %Ecto.Changeset{data: %Author{}}

  """
  def change_author(%Author{} = author, attrs \\ %{}) do
    Author.changeset(author, attrs)
  end
end
