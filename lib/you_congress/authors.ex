defmodule YouCongress.Authors do
  @moduledoc """
  The Authors context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Authors.Author
  alias YouCongress.Votes.Vote

  @doc """
  Returns the list of authors.

  ## Examples

      iex> list_authors()
      [%Author{}, ...]

  """
  def list_authors(opts \\ []) do
    preload = opts[:preload] || []
    base_query = from a in Author, preload: ^preload

    Enum.reduce(
      opts,
      base_query,
      fn
        {:ids, ids}, query ->
          where(query, [author], author.id in ^ids)

        {:search, search}, query ->
          terms = YouCongress.SearchParser.parse(search)

          Enum.reduce(terms, query, fn term, query_acc ->
            term_pattern = "%#{term}%"

            from a in query_acc,
              where:
                ilike(a.name, ^term_pattern) or
                  ilike(a.twitter_username, ^term_pattern)
          end)

        {:twin_origin, twin_origin}, query ->
          where(query, [author], author.twin_origin == ^twin_origin)

        {:twin_enabled, twin_enabled}, query ->
          where(query, [author], author.twin_enabled == ^twin_enabled)

        {:names, names}, query ->
          where(query, [author], author.name in ^names)

        _, query ->
          query
      end
    )
    |> Repo.all()
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
  Gets a an author by id and includes the given tables.
  """
  def get_author!(id, include: tables) do
    Repo.get!(Author, id) |> Repo.preload(tables)
  end

  def get_author_by(opts) do
    query = build_query(opts)
    Repo.one(query)
  end

  def get_author_by!(opts) do
    query = build_query(opts)
    Repo.one!(query)
  end

  defp build_query(opts) do
    base_query = from(a in Author)

    Enum.reduce(
      opts,
      base_query,
      fn
        {:name, name}, query ->
          from a in query, where: a.name == ^name

        {:names, names}, query ->
          from a in query, where: a.name in ^names

        {:wikipedia_url, nil}, query ->
          query

        {:wikipedia_url, wikipedia_url}, query ->
          wikipedia_url = String.downcase(wikipedia_url)
          from a in query, where: fragment("lower(?)", a.wikipedia_url) == ^wikipedia_url

        {:twitter_username, nil}, query ->
          query

        {:twitter_username, twitter_username}, query ->
          twitter_username = String.downcase(twitter_username)
          from a in query, where: fragment("lower(?)", a.twitter_username) == ^twitter_username

        _, query ->
          query
      end
    )
  end

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
  def update_author(
        %Author{twin_enabled: true} = author_before,
        %{"twin_enabled" => "false"} = attrs
      ) do
    update_author_and_delete_twin_options(author_before, attrs)
  end

  def update_author(%Author{twin_enabled: true} = author_before, %{twin_enabled: false} = attrs) do
    update_author_and_delete_twin_options(author_before, attrs)
  end

  def update_author(%Author{} = author_before, attrs) do
    author_before
    |> Author.changeset(attrs)
    |> Repo.update()
  end

  defp update_author_and_delete_twin_options(author_before, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:update_author, Author.changeset(author_before, attrs))
    |> Ecto.Multi.delete_all(
      :delete_votes,
      from(v in Vote, where: v.author_id == ^author_before.id and v.twin)
    )
    |> Repo.transaction()
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
