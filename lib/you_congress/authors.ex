defmodule YouCongress.Authors do
  @moduledoc """
  The Authors context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Authors.Author
  alias YouCongress.Countries
  alias YouCongress.Votes.Vote
  alias YouCongress.Workers.SetAuthorProfileImageFromXWorker

  @doc """
  Returns the list of authors.

  ## Examples

      iex> list_authors()
      [%Author{}, ...]

  """
  def list_authors(opts \\ []) do
    preload = opts[:preload] || []

    opts
    |> build_list_query()
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def count(opts \\ []) do
    opts
    |> build_list_query()
    |> exclude(:order_by)
    |> exclude(:limit)
    |> exclude(:offset)
    |> Repo.aggregate(:count, :id)
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

  def preload(author_or_authors, preloads) do
    Repo.preload(author_or_authors, preloads)
  end

  @doc """
  Gets an author by twitter_id_str first, then falls back to twitter_username.
  Returns nil if no author is found.

  ## Examples

      iex> get_author_by_twitter_id_str_or_username("123456", "johndoe")
      %Author{}

      iex> get_author_by_twitter_id_str_or_username(nil, "johndoe")
      %Author{}

      iex> get_author_by_twitter_id_str_or_username(nil, nil)
      nil

  """
  def get_author_by_twitter_id_str_or_username(nil, nil), do: nil

  def get_author_by_twitter_id_str_or_username(nil, twitter_username) do
    get_author_by(twitter_username: twitter_username)
  end

  def get_author_by_twitter_id_str_or_username(twitter_id_str, twitter_username) do
    # Try to find by twitter_id_str first (more reliable)
    case Repo.get_by(Author, twitter_id_str: twitter_id_str) do
      nil -> get_author_by(twitter_username: twitter_username)
      author -> author
    end
  end

  @doc """
  Gets an author by google_id.
  Returns nil if no author is found.

  ## Examples

      iex> get_author_by_google_id("123456")
      %Author{}

      iex> get_author_by_google_id("unknown")
      nil

  """
  def get_author_by_google_id(nil), do: nil

  def get_author_by_google_id(google_id) do
    Repo.get_by(Author, google_id: google_id)
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
    author = %Author{}

    with {:ok, attrs} <- resolve_country_attrs(attrs) do
      author
      |> Author.changeset(attrs)
      |> Repo.insert()
      |> maybe_enqueue_profile_image_fetch()
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author, attrs, country)}
    end
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
    with {:ok, attrs} <- resolve_country_attrs(attrs) do
      update_author_and_delete_twin_options(author_before, attrs)
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author_before, attrs, country)}
    end
  end

  def update_author(%Author{twin_enabled: true} = author_before, %{twin_enabled: false} = attrs) do
    with {:ok, attrs} <- resolve_country_attrs(attrs) do
      update_author_and_delete_twin_options(author_before, attrs)
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author_before, attrs, country)}
    end
  end

  def update_author(%Author{} = author_before, attrs) do
    with {:ok, attrs} <- resolve_country_attrs(attrs) do
      author_before
      |> Author.changeset(attrs)
      |> Repo.update()
      |> maybe_enqueue_profile_image_fetch()
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author_before, attrs, country)}
    end
  end

  @doc """
  Fetches the author's profile picture from the X API using their X username
  and updates the author's profile_image_url.

  ## Examples

      iex> set_profile_image_from_x(author)
      {:ok, %Author{}}

      iex> set_profile_image_from_x(author_without_twitter_username)
      {:error, :no_twitter_username}

  """
  def set_profile_image_from_x(%Author{twitter_username: nil}),
    do: {:error, :no_twitter_username}

  def set_profile_image_from_x(%Author{twitter_username: twitter_username} = author) do
    with {:ok, %{profile_image_url: profile_image_url}} when is_binary(profile_image_url) <-
           YouCongress.X.XAPI.fetch_user_by_username(twitter_username) do
      update_author(author, %{profile_image_url: profile_image_url})
    else
      {:ok, _} -> {:error, :no_profile_image}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_author_and_delete_twin_options(author_before, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:update_author, Author.changeset(author_before, attrs))
    |> Ecto.Multi.delete_all(
      :delete_votes,
      from(v in Vote, where: v.author_id == ^author_before.id and v.twin)
    )
    |> Repo.transaction()
    |> maybe_enqueue_profile_image_fetch()
  end

  defp maybe_enqueue_profile_image_fetch({:ok, %Author{} = author} = result) do
    enqueue_profile_image_fetch_if_needed(author)
    result
  end

  defp maybe_enqueue_profile_image_fetch({:ok, %{update_author: %Author{} = author}} = result) do
    enqueue_profile_image_fetch_if_needed(author)
    result
  end

  defp maybe_enqueue_profile_image_fetch(result), do: result

  defp enqueue_profile_image_fetch_if_needed(%Author{} = author) do
    if author.profile_image_url in [nil, ""] and author.twitter_username not in [nil, ""] do
      %{author_id: author.id}
      |> SetAuthorProfileImageFromXWorker.new()
      |> Oban.insert()
    end
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

  def update_profile_author(%Author{} = author, attrs, allowed_fields)
      when is_list(allowed_fields) do
    with {:ok, attrs} <- resolve_country_attrs(attrs) do
      author
      |> Author.profile_changeset(attrs, allowed_fields)
      |> Repo.update()
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author, attrs, country)}
    end
  end

  def change_profile_author(%Author{} = author, allowed_fields) when is_list(allowed_fields) do
    change_profile_author(author, %{}, allowed_fields)
  end

  def change_profile_author(%Author{} = author, attrs, allowed_fields)
      when is_list(allowed_fields) do
    Author.profile_changeset(author, attrs, allowed_fields)
  end

  def country_name(%Author{} = author), do: Countries.country_name(author)

  @doc """
  Authors with the most sourced (non-twin) quotes, with their quote
  count. Used for llms.txt.
  """
  def list_top_quoted_authors(limit) do
    from(a in Author,
      join: o in YouCongress.Opinions.Opinion,
      on: o.author_id == a.id,
      where: not is_nil(o.source_url) and o.twin == false and not is_nil(a.name),
      group_by: a.id,
      order_by: [desc: count(o.id)],
      limit: ^limit,
      select: {a, count(o.id)}
    )
    |> Repo.all()
  end

  defp build_list_query(opts) do
    base_query = from(a in Author)

    Enum.reduce(
      opts,
      base_query,
      fn
        {:ids, ids}, query ->
          where(query, [author], author.id in ^ids)

        {:id_less_than, id}, query ->
          where(query, [author], author.id < ^id)

        {:id_greater_than, id}, query ->
          where(query, [author], author.id > ^id)

        {:search, search}, query ->
          terms = YouCongress.SearchParser.parse(search)

          Enum.reduce(terms, query, fn term, query_acc ->
            term_pattern = "%#{term}%"

            from a in query_acc,
              where:
                ilike(a.name, ^term_pattern) or
                  ilike(a.twitter_username, ^term_pattern)
          end)

        {:country_id, nil}, query ->
          where(query, [author], is_nil(author.country_id))

        {:country_id, country_id}, query ->
          where(query, [author], author.country_id == ^country_id)

        {:twin_origin, twin_origin}, query ->
          where(query, [author], author.twin_origin == ^twin_origin)

        {:with_quotes, true}, query ->
          where(
            query,
            [author],
            fragment(
              "EXISTS (SELECT 1 FROM opinions o WHERE o.author_id = ? AND o.source_url IS NOT NULL)",
              author.id
            )
          )

        {:twin_enabled, twin_enabled}, query ->
          where(query, [author], author.twin_enabled == ^twin_enabled)

        {:names, names}, query ->
          where(query, [author], author.name in ^names)

        {:order_by, order_by}, query ->
          order_by(query, ^order_by)

        {:limit, limit}, query ->
          limit(query, ^limit)

        {:offset, offset}, query ->
          offset(query, ^offset)

        _, query ->
          query
      end
    )
  end

  defp resolve_country_attrs(attrs) do
    {country, attrs} = pop_country(attrs)

    cond do
      blank?(country) or country_id_present?(attrs) ->
        {:ok, attrs}

      true ->
        case Countries.get_country_by_name_or_iso(country) do
          nil -> {:error, :unknown_country, country, attrs}
          country -> {:ok, Map.put(attrs, :country_id, country.id)}
        end
    end
  end

  defp pop_country(%{} = attrs) do
    case Map.pop(attrs, :country) do
      {nil, attrs} -> Map.pop(attrs, "country")
      {country, attrs} -> {country, Map.delete(attrs, "country")}
    end
  end

  defp country_id_present?(attrs) do
    attrs
    |> country_id_value()
    |> blank?()
    |> Kernel.not()
  end

  defp country_id_value(attrs), do: Map.get(attrs, :country_id) || Map.get(attrs, "country_id")

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp unknown_country_changeset(%Author{} = author, attrs, country) do
    author
    |> Author.changeset(attrs)
    |> Ecto.Changeset.add_error(:country_id, "does not match an existing country",
      country: country
    )
  end
end
