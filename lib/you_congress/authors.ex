defmodule YouCongress.Authors do
  @moduledoc """
  The Authors context.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Authors.Author
  alias YouCongress.Accounts.User
  alias YouCongress.Countries
  alias YouCongress.Delegations.Delegation
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote
  alias YouCongress.VoteVerifications.VoteVerification
  alias YouCongress.Workers.SetAuthorXProfileDataWorker
  alias YouCongress.Workers.SetAuthorWikidataWorker

  @profile_merge_fields [
    :name,
    :twitter_id_str,
    :profile_image_url,
    :description,
    :followers_count,
    :friends_count,
    :verified,
    :location,
    :twitter_username,
    :google_id,
    :bio,
    :wikipedia_url,
    :wikidata,
    :country_id
  ]

  @x_profile_fields [
    :twitter_id_str,
    :description,
    :followers_count,
    :friends_count,
    :verified,
    :location,
    :google_id
  ]

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
      changeset = reset_wikidata_if_url_changed(Author.changeset(author, attrs))

      changeset
      |> Repo.insert()
      |> maybe_enqueue_x_profile_data_fetch()
      |> maybe_enqueue_wikidata_fetch(wikipedia_url_changed?(changeset))
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
  Finds a author by X/Twitter username or creates a new one.
  """
  def find_by_twitter_username_or_create(%{"twitter_username" => twitter_username} = author_data) do
    case find_by(:twitter_username, twitter_username) do
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
  def find_by(:name, name), do: find_one_exact(:name, name)

  def find_by(:wikipedia_url, wikipedia_url),
    do: find_one_case_insensitive(:wikipedia_url, wikipedia_url)

  def find_by(:twitter_username, username),
    do: find_one_case_insensitive(:twitter_username, username)

  defp find_one_exact(_column, value) when value in [nil, ""], do: nil

  defp find_one_exact(column, value) when is_binary(value) do
    from(a in Author,
      where: field(a, ^column) == ^value,
      order_by: [asc: a.id],
      limit: 1
    )
    |> Repo.one()
  end

  defp find_one_exact(_column, _value), do: nil

  defp find_one_case_insensitive(_column, value) when value in [nil, ""], do: nil

  defp find_one_case_insensitive(column, value) when is_binary(value) do
    value = value |> String.trim() |> String.downcase()

    from(a in Author,
      where: fragment("lower(?)", field(a, ^column)) == ^value,
      order_by: [asc: a.id],
      limit: 1
    )
    |> Repo.one()
  end

  defp find_one_case_insensitive(_column, _value), do: nil

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
      changeset = reset_wikidata_if_url_changed(Author.changeset(author_before, attrs))
      twitter_username_changed? = twitter_username_changed?(changeset)

      changeset
      |> Repo.update()
      |> maybe_enqueue_x_profile_data_fetch(twitter_username_changed?)
      |> maybe_enqueue_wikidata_fetch(wikipedia_url_changed?(changeset))
    else
      {:error, :unknown_country, country, attrs} ->
        {:error, unknown_country_changeset(author_before, attrs, country)}
    end
  end

  @doc """
  Fetches the author's profile from the X API using their X username and
  updates X-sourced author fields. The profile image is only updated when the
  author does not already have one.

  ## Examples

      iex> set_x_profile_data(author)
      {:ok, %Author{}}

      iex> set_x_profile_data(author_without_twitter_username)
      {:error, :no_twitter_username}

  """
  def set_x_profile_data(%Author{twitter_username: nil}),
    do: {:error, :no_twitter_username}

  def set_x_profile_data(%Author{twitter_username: twitter_username} = author) do
    with {:ok, x_user_data} <- YouCongress.X.XAPI.fetch_user_by_username(twitter_username) do
      attrs = x_profile_attrs(author, x_user_data)

      if map_size(attrs) > 0 do
        update_author_from_x_profile(author, attrs)
      else
        {:error, :no_profile_image}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_author_and_delete_twin_options(author_before, attrs) do
    changeset = reset_wikidata_if_url_changed(Author.changeset(author_before, attrs))
    twitter_username_changed? = twitter_username_changed?(changeset)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:update_author, changeset)
    |> Ecto.Multi.delete_all(
      :delete_votes,
      from(v in Vote, where: v.author_id == ^author_before.id and v.twin)
    )
    |> Repo.transaction()
    |> maybe_enqueue_x_profile_data_fetch(twitter_username_changed?)
    |> maybe_enqueue_wikidata_fetch(wikipedia_url_changed?(changeset))
  end

  defp maybe_enqueue_x_profile_data_fetch(result, force? \\ false)

  defp maybe_enqueue_x_profile_data_fetch({:ok, %Author{} = author} = result, force?) do
    enqueue_x_profile_data_fetch_if_needed(author, force?)
    result
  end

  defp maybe_enqueue_x_profile_data_fetch(
         {:ok, %{update_author: %Author{} = author}} = result,
         force?
       ) do
    enqueue_x_profile_data_fetch_if_needed(author, force?)
    result
  end

  defp maybe_enqueue_x_profile_data_fetch(result, _force?), do: result

  defp enqueue_x_profile_data_fetch_if_needed(%Author{} = author, force?) do
    should_fetch? =
      author.twitter_username not in [nil, ""] and
        (force? or author.profile_image_url in [nil, ""])

    if should_fetch? do
      %{author_id: author.id}
      |> SetAuthorXProfileDataWorker.new()
      |> Oban.insert()
    end
  end

  # When the wikipedia_url changes the stored wikidata id is stale, so we clear
  # it (unless the caller set one explicitly) and let the worker resolve it again.
  defp reset_wikidata_if_url_changed(%Ecto.Changeset{} = changeset) do
    if wikipedia_url_changed?(changeset) and not Map.has_key?(changeset.changes, :wikidata) do
      Ecto.Changeset.put_change(changeset, :wikidata, nil)
    else
      changeset
    end
  end

  defp wikipedia_url_changed?(%Ecto.Changeset{changes: changes}) do
    Map.has_key?(changes, :wikipedia_url)
  end

  defp twitter_username_changed?(%Ecto.Changeset{changes: changes}) do
    Map.has_key?(changes, :twitter_username)
  end

  defp x_profile_attrs(%Author{} = author, x_user_data) do
    @x_profile_fields
    |> Enum.reduce(%{}, fn field, attrs ->
      put_present_x_attr(attrs, x_user_data, field)
    end)
    |> maybe_put_profile_image(author, x_user_data)
  end

  defp put_present_x_attr(attrs, x_user_data, field) do
    case Map.fetch(x_user_data, field) do
      {:ok, nil} -> attrs
      {:ok, value} -> Map.put(attrs, field, value)
      :error -> attrs
    end
  end

  defp maybe_put_profile_image(attrs, %Author{profile_image_url: image_url}, _x_user_data)
       when image_url not in [nil, ""] do
    attrs
  end

  defp maybe_put_profile_image(attrs, %Author{}, x_user_data) do
    case Map.fetch(x_user_data, :profile_image_url) do
      {:ok, profile_image_url} when is_binary(profile_image_url) and profile_image_url != "" ->
        Map.put(attrs, :profile_image_url, profile_image_url)

      _ ->
        attrs
    end
  end

  defp update_author_from_x_profile(%Author{} = author, attrs) do
    author
    |> Author.changeset(attrs)
    |> Repo.update()
  end

  defp maybe_enqueue_wikidata_fetch({:ok, %Author{} = author} = result, true) do
    enqueue_wikidata_fetch_if_needed(author)
    result
  end

  defp maybe_enqueue_wikidata_fetch({:ok, %{update_author: %Author{} = author}} = result, true) do
    enqueue_wikidata_fetch_if_needed(author)
    result
  end

  defp maybe_enqueue_wikidata_fetch(result, _wikipedia_url_changed?), do: result

  defp enqueue_wikidata_fetch_if_needed(%Author{id: id, wikipedia_url: url})
       when is_binary(url) and url != "" do
    %{author_id: id}
    |> SetAuthorWikidataWorker.new()
    |> Oban.insert()
  end

  defp enqueue_wikidata_fetch_if_needed(_author), do: :ok

  @doc """
  Merges two authors into one author and deletes the detached duplicate.

  The surviving author is selected by the highest opinion count, then the
  highest vote count, then the first argument. Blank profile fields on the
  survivor are filled from the merged author.
  """
  def merge_authors(first_author_id, second_author_id) do
    first_author_id = normalize_author_id!(first_author_id)
    second_author_id = normalize_author_id!(second_author_id)

    if first_author_id == second_author_id do
      {:error, :same_author}
    else
      Repo.transaction(fn ->
        first_author = Repo.get!(Author, first_author_id)
        second_author = Repo.get!(Author, second_author_id)

        {survivor, duplicate, survivor_stats, duplicate_stats} =
          choose_merge_survivor(first_author, second_author)

        profile_attrs = fill_blank_profile_attrs(survivor, duplicate)
        affected_deleguee_ids = affected_merge_deleguee_ids(duplicate.id, survivor.id)
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        moved_users = move_author_users(duplicate.id, survivor.id, now)
        moved_opinions = move_author_opinions(duplicate.id, survivor.id, now)
        vote_counts = merge_author_votes(duplicate.id, survivor.id, now)
        delegation_counts = merge_author_delegations(duplicate.id, survivor.id, now)

        ensure_author_detached!(duplicate.id)
        deleted_author = delete_duplicate_author!(duplicate)
        updated_survivor = update_survivor_profile!(survivor, profile_attrs)
        delegated_vote_refreshes = refresh_affected_delegated_votes(affected_deleguee_ids)

        %{
          author: updated_survivor,
          deleted_author: deleted_author,
          survivor_id: survivor.id,
          merged_author_id: duplicate.id,
          survivor_stats: survivor_stats,
          merged_author_stats: duplicate_stats,
          counts: %{
            users: moved_users,
            opinions: moved_opinions,
            votes: vote_counts,
            delegations: delegation_counts,
            delegated_vote_refreshes: delegated_vote_refreshes
          }
        }
      end)
    end
  end

  defp normalize_author_id!(id) when is_integer(id), do: id
  defp normalize_author_id!(id) when is_binary(id), do: String.to_integer(id)

  defp choose_merge_survivor(%Author{} = first_author, %Author{} = second_author) do
    first_stats = author_merge_stats(first_author.id)
    second_stats = author_merge_stats(second_author.id)

    cond do
      first_stats.opinions > second_stats.opinions ->
        {first_author, second_author, first_stats, second_stats}

      second_stats.opinions > first_stats.opinions ->
        {second_author, first_author, second_stats, first_stats}

      first_stats.votes > second_stats.votes ->
        {first_author, second_author, first_stats, second_stats}

      second_stats.votes > first_stats.votes ->
        {second_author, first_author, second_stats, first_stats}

      true ->
        {first_author, second_author, first_stats, second_stats}
    end
  end

  defp author_merge_stats(author_id) do
    %{
      opinions: Repo.aggregate(from(o in Opinion, where: o.author_id == ^author_id), :count, :id),
      votes: Repo.aggregate(from(v in Vote, where: v.author_id == ^author_id), :count, :id)
    }
  end

  defp fill_blank_profile_attrs(%Author{} = survivor, %Author{} = duplicate) do
    Enum.reduce(@profile_merge_fields, %{}, fn field, attrs ->
      survivor_value = Map.get(survivor, field)
      duplicate_value = Map.get(duplicate, field)

      if blank?(survivor_value) and not blank?(duplicate_value) do
        Map.put(attrs, field, duplicate_value)
      else
        attrs
      end
    end)
  end

  defp affected_merge_deleguee_ids(duplicate_author_id, survivor_author_id) do
    from(d in Delegation,
      where: d.delegate_id in ^[duplicate_author_id, survivor_author_id],
      select: d.deleguee_id
    )
    |> Repo.all()
    |> then(&[survivor_author_id | &1])
    |> Enum.reject(&(&1 == duplicate_author_id))
    |> Enum.uniq()
  end

  defp move_author_users(duplicate_author_id, survivor_author_id, now) do
    {count, _} =
      from(u in User, where: u.author_id == ^duplicate_author_id)
      |> Repo.update_all(set: [author_id: survivor_author_id, updated_at: now])

    count
  end

  defp move_author_opinions(duplicate_author_id, survivor_author_id, now) do
    {count, _} =
      from(o in Opinion, where: o.author_id == ^duplicate_author_id)
      |> Repo.update_all(set: [author_id: survivor_author_id, updated_at: now])

    count
  end

  defp merge_author_votes(duplicate_author_id, survivor_author_id, now) do
    conflicts = conflicting_votes(duplicate_author_id, survivor_author_id)
    duplicate_vote_ids = Enum.map(conflicts, & &1.duplicate_vote_id)
    survivor_vote_ids = conflicts |> Enum.map(& &1.survivor_vote_id) |> Enum.uniq()

    merged_conflicting_votes =
      Enum.reduce(conflicts, 0, fn conflict, count ->
        merge_conflicting_vote!(conflict)
        count + 1
      end)

    moved_vote_verifications = move_vote_verifications(conflicts)
    deleted_duplicate_votes = delete_duplicate_votes(duplicate_vote_ids)
    moved_votes = move_non_conflicting_votes(duplicate_author_id, survivor_author_id, now)

    Enum.each(survivor_vote_ids, &YouCongress.VoteVerifications.update_vote_verification_status/1)

    %{
      moved: moved_votes,
      merged: merged_conflicting_votes,
      deleted_duplicates: deleted_duplicate_votes,
      moved_verifications: moved_vote_verifications
    }
  end

  defp conflicting_votes(duplicate_author_id, survivor_author_id) do
    from(duplicate_vote in Vote,
      join: survivor_vote in Vote,
      on:
        survivor_vote.author_id == ^survivor_author_id and
          survivor_vote.statement_id == duplicate_vote.statement_id,
      where: duplicate_vote.author_id == ^duplicate_author_id,
      select: %{
        duplicate_vote_id: duplicate_vote.id,
        survivor_vote_id: survivor_vote.id
      }
    )
    |> Repo.all()
  end

  defp merge_conflicting_vote!(%{
         duplicate_vote_id: duplicate_vote_id,
         survivor_vote_id: survivor_vote_id
       }) do
    duplicate_vote = Repo.get!(Vote, duplicate_vote_id) |> Repo.preload(:opinion)
    survivor_vote = Repo.get!(Vote, survivor_vote_id) |> Repo.preload(:opinion)
    preferred_vote = preferred_conflicting_vote(survivor_vote, duplicate_vote)

    attrs = %{
      answer: merged_vote_answer(survivor_vote, duplicate_vote, preferred_vote),
      direct: survivor_vote.direct || duplicate_vote.direct,
      twin: survivor_vote.twin && duplicate_vote.twin,
      opinion_id: merged_opinion_id(survivor_vote, duplicate_vote, preferred_vote)
    }

    survivor_vote
    |> Vote.changeset(attrs)
    |> Repo.update!()

    # A vote holds a single opinion, but an author may have several sourced
    # quotes on the same statement. Collapsing two votes into one would orphan
    # the opinion the surviving vote no longer points at, so keep every sourced
    # opinion linked to the statement: they resurface as alternate opinions.
    preserve_sourced_opinions!(survivor_vote.statement_id, [
      survivor_vote.opinion,
      duplicate_vote.opinion
    ])
  end

  # Keep the surviving vote pointing at a sourced opinion when one is available,
  # so it counts as a sourced-opinion vote and its alternate quotes are surfaced.
  defp merged_opinion_id(survivor_vote, duplicate_vote, preferred_vote) do
    sourced_opinion_id =
      [preferred_vote, survivor_vote, duplicate_vote]
      |> Enum.map(& &1.opinion)
      |> Enum.find(fn opinion -> opinion && not is_nil(opinion.source_url) end)
      |> case do
        nil -> nil
        opinion -> opinion.id
      end

    sourced_opinion_id || preferred_vote.opinion_id || survivor_vote.opinion_id ||
      duplicate_vote.opinion_id
  end

  defp preserve_sourced_opinions!(statement_id, opinions) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      opinions
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(not is_nil(&1.source_url)))
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(fn opinion ->
        %{
          opinion_id: opinion.id,
          statement_id: statement_id,
          user_id: opinion.user_id,
          verification_status: opinion.verification_status,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows != [] do
      Repo.insert_all(OpinionStatement, rows,
        on_conflict: :nothing,
        conflict_target: [:opinion_id, :statement_id]
      )
    end
  end

  defp preferred_conflicting_vote(_survivor_vote, %Vote{opinion_id: opinion_id} = duplicate_vote)
       when not is_nil(opinion_id),
       do: duplicate_vote

  defp preferred_conflicting_vote(%Vote{opinion_id: opinion_id} = survivor_vote, _duplicate_vote)
       when not is_nil(opinion_id),
       do: survivor_vote

  defp preferred_conflicting_vote(%Vote{direct: false}, %Vote{direct: true} = duplicate_vote),
    do: duplicate_vote

  defp preferred_conflicting_vote(survivor_vote, _duplicate_vote), do: survivor_vote

  defp merged_vote_answer(_survivor_vote, _duplicate_vote, %Vote{answer: answer}), do: answer

  defp move_vote_verifications(conflicts) do
    Enum.reduce(conflicts, 0, fn %{
                                   duplicate_vote_id: duplicate_vote_id,
                                   survivor_vote_id: survivor_vote_id
                                 },
                                 count ->
      {moved, _} =
        from(v in VoteVerification, where: v.vote_id == ^duplicate_vote_id)
        |> Repo.update_all(set: [vote_id: survivor_vote_id])

      count + moved
    end)
  end

  defp delete_duplicate_votes([]), do: 0

  defp delete_duplicate_votes(duplicate_vote_ids) do
    {count, _} =
      from(v in Vote, where: v.id in ^duplicate_vote_ids)
      |> Repo.delete_all()

    count
  end

  defp move_non_conflicting_votes(duplicate_author_id, survivor_author_id, now) do
    {count, _} =
      from(v in Vote, where: v.author_id == ^duplicate_author_id)
      |> Repo.update_all(set: [author_id: survivor_author_id, updated_at: now])

    count
  end

  defp merge_author_delegations(duplicate_author_id, survivor_author_id, now) do
    self_delegations = delete_self_merge_delegations(duplicate_author_id, survivor_author_id)

    duplicate_deleguee_rows =
      delete_duplicate_deleguee_delegations(duplicate_author_id, survivor_author_id)

    duplicate_delegate_rows =
      delete_duplicate_delegate_delegations(duplicate_author_id, survivor_author_id)

    moved_deleguee_rows = move_deleguee_delegations(duplicate_author_id, survivor_author_id, now)
    moved_delegate_rows = move_delegate_delegations(duplicate_author_id, survivor_author_id, now)

    %{
      moved_deleguee: moved_deleguee_rows,
      moved_delegate: moved_delegate_rows,
      deleted_self: self_delegations,
      deleted_duplicates: duplicate_deleguee_rows + duplicate_delegate_rows
    }
  end

  defp delete_self_merge_delegations(duplicate_author_id, survivor_author_id) do
    {count, _} =
      from(d in Delegation,
        where:
          d.deleguee_id in ^[duplicate_author_id, survivor_author_id] and
            d.delegate_id in ^[duplicate_author_id, survivor_author_id]
      )
      |> Repo.delete_all()

    count
  end

  defp delete_duplicate_deleguee_delegations(duplicate_author_id, survivor_author_id) do
    {count, _} =
      from(d in Delegation,
        where: d.deleguee_id == ^duplicate_author_id,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM delegations target WHERE target.deleguee_id = ? AND target.delegate_id = ?)",
            ^survivor_author_id,
            d.delegate_id
          )
      )
      |> Repo.delete_all()

    count
  end

  defp delete_duplicate_delegate_delegations(duplicate_author_id, survivor_author_id) do
    {count, _} =
      from(d in Delegation,
        where: d.delegate_id == ^duplicate_author_id,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM delegations target WHERE target.delegate_id = ? AND target.deleguee_id = ?)",
            ^survivor_author_id,
            d.deleguee_id
          )
      )
      |> Repo.delete_all()

    count
  end

  defp move_deleguee_delegations(duplicate_author_id, survivor_author_id, now) do
    {count, _} =
      from(d in Delegation, where: d.deleguee_id == ^duplicate_author_id)
      |> Repo.update_all(set: [deleguee_id: survivor_author_id, updated_at: now])

    count
  end

  defp move_delegate_delegations(duplicate_author_id, survivor_author_id, now) do
    {count, _} =
      from(d in Delegation, where: d.delegate_id == ^duplicate_author_id)
      |> Repo.update_all(set: [delegate_id: survivor_author_id, updated_at: now])

    count
  end

  defp ensure_author_detached!(author_id) do
    if author_linked?(author_id) do
      Repo.rollback({:author_still_linked, author_id})
    end
  end

  defp author_linked?(author_id) do
    Repo.exists?(from(u in User, where: u.author_id == ^author_id)) ||
      Repo.exists?(from(o in Opinion, where: o.author_id == ^author_id)) ||
      Repo.exists?(from(v in Vote, where: v.author_id == ^author_id)) ||
      Repo.exists?(
        from(d in Delegation,
          where: d.deleguee_id == ^author_id or d.delegate_id == ^author_id
        )
      )
  end

  defp delete_duplicate_author!(%Author{} = duplicate) do
    case Repo.delete(duplicate) do
      {:ok, deleted_author} -> deleted_author
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_survivor_profile!(%Author{} = survivor, attrs) when attrs == %{} do
    Repo.get!(Author, survivor.id)
  end

  defp update_survivor_profile!(%Author{} = survivor, attrs) do
    case update_author(survivor, attrs) do
      {:ok, %Author{} = updated_author} -> updated_author
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp refresh_affected_delegated_votes(author_ids) do
    Enum.each(author_ids, &YouCongress.DelegationVotes.update_author_delegated_votes/1)
    length(author_ids)
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
