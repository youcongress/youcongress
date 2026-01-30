defmodule YouCongress.Opinions do
  @moduledoc """
  The context for sourced quotes and user opinions.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Likes
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Workers.UpdateOpinionDescendantsCountWorker

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

  @doc """
  Gets a single opinion.

  Returns `nil` if the Opinion does not exist.

  ## Examples

      iex> get_opinion(123)
      %Opinion{}

      iex> get_opinion(456)
      nil

  """
  def get_opinion(nil), do: nil
  def get_opinion(id) when is_integer(id) or is_binary(id), do: Repo.get(Opinion, id)

  def get_opinion(id, preload: tables) do
    Repo.get(Opinion, id)
    |> Repo.preload(tables)
  end

  def get_by(opts) do
    query = build_query(opts)
    Repo.one(query)
  end

  @doc """
  Creates a opinion.

  ## Examples

      iex> create_opinion(%{field: value})
      {:ok, %Opinion{}}

      iex> create_opinion(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_opinion(attrs \\ %{}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:opinion, Opinion.changeset(%Opinion{}, attrs))
    |> enqueue_update_ancestor_counts(attrs["ancestry"])
    |> Repo.transaction()
  end

  defp enqueue_update_ancestor_counts(multi, nil), do: multi

  defp enqueue_update_ancestor_counts(multi, ancestry) do
    ascestor_ids = String.split(ancestry, "/")

    Enum.reduce(ascestor_ids, multi, fn ascestor_id, multi ->
      Ecto.Multi.insert(
        multi,
        "update_ancestor_id_#{ascestor_id}",
        UpdateOpinionDescendantsCountWorker.new(%{"opinion_id" => ascestor_id})
      )
    end)
  end

  defp handle_transaction_result({:ok, %{opinion: opinion}}), do: {:ok, opinion}

  defp handle_transaction_result({:error, _, failed_operation, _changes}) do
    {:error, failed_operation}
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
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:opinion, opinion)
    |> enqueue_update_ancestor_counts(opinion.ancestry)
    |> Repo.transaction()
    |> handle_transaction_result()
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
      {:ids, ids}, query ->
        from q in query, where: q.id in ^ids

      {:exclude_ids, exclude_ids}, query ->
        from q in query, where: q.id not in ^exclude_ids

      {:author_ids, author_ids}, query ->
        from q in query, where: q.author_id in ^author_ids

      {:statement_ids, statement_ids}, query ->
        from q in query,
          join: ov in "opinions_statements",
          on: ov.opinion_id == q.id,
          where: ov.statement_id in ^statement_ids

      {:hall_name, hall_name}, query when not is_nil(hall_name) ->
        # Use a subquery to avoid DISTINCT ON ordering issues
        hall_opinion_ids =
          from q in Opinion,
            join: ov in "opinions_statements",
            on: ov.opinion_id == q.id,
            join: v in "statements",
            on: ov.statement_id == v.id,
            join: hv in "halls_statements",
            on: hv.statement_id == v.id,
            join: h in "halls",
            on: hv.hall_id == h.id,
            where: h.name == ^hall_name,
            select: q.id

        from q in query, where: q.id in subquery(hall_opinion_ids)

      {:has_statements, true}, query ->
        from q in query,
          join: ov in "opinions_statements",
          on: ov.opinion_id == q.id,
          distinct: q.id

      {:content, content}, query ->
        from q in query, where: q.content == ^content

      {:content_contains, content}, query ->
        from q in query, where: ilike(q.content, ^"%#{content}%")

      {:search, search}, query ->
        terms = YouCongress.SearchParser.parse(search)

        Enum.reduce(terms, query, fn term, query_acc ->
          term_pattern = "%#{term}%"

          from q in query_acc,
            join: a in assoc(q, :author),
            where: ilike(q.content, ^term_pattern) or ilike(a.name, ^term_pattern)
        end)

      {:initial_ancestry, ancestry}, query ->
        from q in query, where: fragment("? LIKE ?", q.ancestry, ^"#{ancestry}/%")

      {:ancestry, nil}, query ->
        from q in query, where: is_nil(q.ancestry)

      {:ancestry, ancestry}, query ->
        from q in query, where: q.ancestry == ^"#{ancestry}"

      {:only_quotes, true}, query ->
        from q in query, where: not is_nil(q.source_url)

      {:twin, twin_value}, query ->
        from q in query, where: q.twin == ^twin_value

      {:include_twins, include_twins}, query ->
        from q in query, where: q.twin == ^include_twins or q.twin == false

      {:is_verified, true}, query ->
        from q in query, where: not is_nil(q.verified_at)

      {:is_verified, false}, query ->
        from q in query, where: is_nil(q.verified_at)

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
    result = Repo.delete_all(from o in Opinion, where: o.id in ^subtree_ids)

    Ecto.Multi.new()
    |> enqueue_update_ancestor_counts(opinion.ancestry)
    |> Repo.transaction()

    result
  end

  def update_descendants_count(%Opinion{} = opinion) do
    count = length(Opinion.descendant_ids(opinion))

    changeset = Opinion.changeset(opinion, %{descendants_count: count})
    Repo.update(changeset)
  end

  def update_opinion_likes_count(opinion_id) when is_number(opinion_id) do
    case get_opinion(opinion_id) do
      nil -> {:error, "Opinion not found"}
      opinion -> update_opinion_likes_count(opinion)
    end
  end

  def update_opinion_likes_count(%Opinion{} = opinion) do
    count = Likes.count(opinion_id: opinion.id)

    changeset = Opinion.changeset(opinion, %{likes_count: count})
    Repo.update(changeset)
  end

  def delete_subopinions(%Opinion{} = opinion) do
    descendant_ids = Opinion.descendant_ids(opinion)
    result = Repo.delete_all(from o in Opinion, where: o.id in ^descendant_ids)
    update_descendants_count(opinion)
    result
  end

  def count do
    from(o in Opinion, select: count(o.id))
    |> Repo.one()
  end

  @doc """
  Adds an opinion to a statement by creating an association in the opinions_statements table.

  ## Examples

      iex> add_opinion_to_statement(opinion, statement)
      {:ok, %Opinion{}}

      iex> add_opinion_to_statement(opinion, statement)
      {:error, %Ecto.Changeset{}}
  """
  def add_opinion_to_statement(%Opinion{} = opinion, statement_id)
      when is_integer(statement_id) do
    statement = YouCongress.Statements.get_statement!(statement_id)
    add_opinion_to_statement(opinion, statement)
  end

  def add_opinion_to_statement(
        %Opinion{} = opinion,
        %YouCongress.Statements.Statement{} = statement
      ) do
    add_opinion_to_statement(opinion, statement, opinion.user_id)
  end

  def add_opinion_to_statement(
        %Opinion{} = opinion,
        %YouCongress.Statements.Statement{} = statement,
        user_id
      )
      when not is_nil(user_id) do
    # Check if the opinion is already associated with this statement
    existing_association =
      Repo.get_by(OpinionStatement,
        opinion_id: opinion.id,
        statement_id: statement.id
      )

    if existing_association do
      {:error, :already_associated}
    else
      # Create the association with the user_id
      %OpinionStatement{}
      |> OpinionStatement.changeset(%{
        opinion_id: opinion.id,
        statement_id: statement.id,
        user_id: user_id
      })
      |> Repo.insert()
      |> case do
        {:ok, _opinion_statement} ->
          # Return the updated opinion for consistency
          {:ok, Repo.preload(opinion, :statements)}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def add_opinion_to_statement(
        %Opinion{} = _opinion,
        %YouCongress.Statements.Statement{} = _statement,
        _user_id
      ) do
    {:error, :user_id_required}
  end
end
