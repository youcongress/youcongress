defmodule YouCongress.Statements do
  @moduledoc """
  The Statements context.

  A statement is a claim or proposal that authors can support, oppose, abstain and add opinions to.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Statements.Statement
  alias YouCongress.HallsStatements
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Workers.StatementHallsGeneratorWorker
  alias YouCongress.Votes.Vote

  @doc """
  Returns the list of statements.

  ## Examples

      iex> list_statements()
      [%Statement{}, ...]

  """
  def list_statements do
    Repo.all(Statement)
  end

  @doc """
  Returns the list of statements ordered by `order_by`.

  ## Examples

      iex> list_statements(order: desc)
      [%Statement{}, ...]

  """
  def list_statements(opts) do
    preload = opts[:preload] || []

    base_query = from(v in Statement)

    query =
      Enum.reduce(
        opts,
        base_query,
        fn
          {:hall_name, hall_name}, query ->
            from(v in query,
              join: h in assoc(v, :halls),
              where: h.name == ^hall_name,
              distinct: true
            )

          {:title_contains, title}, query ->
            where(query, [v], ilike(v.title, ^"%#{title}%"))

          {:search, search}, query ->
            terms = YouCongress.SearchParser.parse(search)

            Enum.reduce(terms, query, fn term, query_acc ->
              term_pattern = "%#{term}%"
              where(query_acc, [v], ilike(v.title, ^term_pattern))
            end)

          {:order, :updated_at_desc}, query ->
            order_by(query, desc: :updated_at)

          {:order, :opinion_likes_count_desc}, query ->
            order_by(query, desc: :opinion_likes_count, desc: :inserted_at)

          {:order, :inserted_at_desc}, query ->
            order_by(query, desc: :inserted_at)

          {:order, :desc}, query ->
            order_by(query, desc: :updated_at)

          {:order, :random}, query ->
            order_by(query, fragment("RANDOM()"))

          {:limit, limit}, query ->
            limit(query, ^limit)

          {:offset, offset}, query ->
            offset(query, ^offset)

          _, query ->
            query
        end
      )

    query
    |> Repo.all()
    |> Repo.preload(preload)
  end

  def list_random_statements(except_id, limit) do
    Repo.all(
      from v in Statement,
        where: v.id != ^except_id,
        order_by: fragment("RANDOM()"),
        limit: ^limit
    )
  end

  def list_statements_with_opinions_by_authors(author_ids) do
    opinions_query =
      from o in Opinion,
        where: o.author_id in ^author_ids,
        order_by: [desc: :likes_count],
        preload: [:author]

    votes_query =
      from v in Vote,
        where: v.author_id in ^author_ids

    from(v in Statement)
    |> join(:inner, [v], ov in "opinions_statements", on: ov.statement_id == v.id)
    |> join(:inner, [v, ov], o in Opinion, on: ov.opinion_id == o.id)
    |> where([v, ov, o], o.author_id in ^author_ids)
    |> distinct(true)
    |> preload(opinions: ^opinions_query, votes: ^votes_query)
    |> Repo.all()
    |> filter_latest_opinions_for_statements()
  end

  defp filter_latest_opinions_for_statements(statements) do
    Enum.map(statements, fn statement ->
      unique_opinions =
        statement.opinions
        |> Enum.group_by(& &1.author_id)
        |> Enum.map(fn {_author_id, opinions} ->
          Enum.max_by(opinions, & &1.id)
        end)
        |> Enum.sort_by(& &1.likes_count, :desc)

      %{statement | opinions: unique_opinions}
    end)
  end

  @doc """
  Gets a statement given some params.

  ## Examples

      iex> get_statement!(%{title: "Yey"})
      %Statement{}

      iex> get_statement!(33)
      %Statement{}
  """
  @spec get_statement!(list | integer) :: Statement.t()
  def get_statement!(options) when is_list(options) do
    Repo.get_by!(Statement, options)
  end

  def get_statement!(id), do: Repo.get!(Statement, id)

  def get_statement(id) do
    Repo.get(Statement, id)
  end

  @doc """
  Gets a single statement with a table preloaded such as votes and authors.

  Raises `Ecto.NoResultsError` if the Statement does not exist.

  ## Examples

      iex> get_statement!(123, preload: [:votes])
      %Statement{}
  """
  def get_statement!(id, preload: tables) do
    Repo.get!(Statement, id) |> Repo.preload(tables)
  end

  @doc """
  Creates a statement.

  ## Examples

      iex> create_statement(%{field: value})
      {:ok, %Statement{}}

      iex> create_statement(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_statement(attrs \\ %{}) do
    statement_changeset = Statement.changeset(%Statement{}, attrs)

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:statement, statement_changeset)
      |> Oban.insert(:job, fn %{statement: statement} ->
        StatementHallsGeneratorWorker.new(%{statement_id: statement.id})
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{statement: statement}} -> {:ok, statement}
      {:error, :statement, error, _} -> {:error, error}
      {:error, _, _, _} -> {:error, %Ecto.Changeset{}}
    end
  end

  @doc """
  Updates a statement.

  ## Examples

      iex> update_statement(statement, %{field: new_value})
      {:ok, %Statement{}}

      iex> update_statement(statement, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_statement(%Statement{} = statement, attrs) do
    result =
      statement
      |> Statement.changeset(attrs)
      |> Repo.update()

    with {:ok, new_statement} <- result do
      if attrs[:title] && attrs[:title] != statement.title do
        # Only admins can update statement so it's ok to:
        # 1. do it synchronously
        # 2. raise an error if it fails
        HallsStatements.sync!(new_statement.id)
      end

      {:ok, new_statement}
    end
  end

  @doc """
  Deletes a statement.

  ## Examples

      iex> delete_statement(statement)
      {:ok, %Statement{}}

      iex> delete_statement(statement)
      {:error, %Ecto.Changeset{}}

  """
  def delete_statement(%Statement{} = statement) do
    YouCongress.HallsStatements.delete_halls_statements(statement)
    Repo.delete(statement)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking statement changes.

  ## Examples

      iex> change_statement(statement)
      %Ecto.Changeset{data: %Statement{}}

  """
  def change_statement(%Statement{} = statement, attrs \\ %{}) do
    Statement.changeset(statement, attrs)
  end

  @doc """
  Returns the number of statements.

  ## Examples

      > count()
      42

  """
  def count do
    Repo.aggregate(Statement, :count, :id)
  end

  @doc """
  Returns the statement with the given slug.
  """

  def get_by(opts) do
    Repo.get_by(Statement, opts)
  end

  def get_by!(opts) do
    Repo.get_by!(Statement, opts)
  end

  def regenerate_slug(statement) do
    statement
    |> Statement.changeset(%{slug: nil})
    |> Repo.update()
  end

  def regenerate_all_statement_slugs do
    Repo.all(Statement)
    |> Enum.each(&regenerate_slug/1)
  end

  def sync_opinion_likes_count(statement) do
    count =
      from(o in Opinion,
        join: ov in "opinions_statements",
        on: ov.opinion_id == o.id,
        where: ov.statement_id == ^statement.id and is_nil(o.ancestry),
        select: coalesce(sum(o.likes_count), 0)
      )
      |> Repo.one() || 0

    update_statement(statement, %{opinion_likes_count: count})
  end

  def statements_count_created_in_the_last_hour do
    from(v in Statement, where: v.inserted_at > ago(1, "hour"), select: count(v.id))
    |> Repo.one()
  end

  def touch_statement(statement) do
    statement
    |> Statement.changeset(%{updated_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
