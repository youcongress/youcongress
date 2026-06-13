defmodule YouCongress.Opinions do
  @moduledoc """
  The context for sourced quotes and user opinions.
  """

  import Ecto.Query, warn: false
  import Pgvector.Ecto.Query, only: [cosine_distance: 2]
  alias YouCongress.Repo

  alias YouCongress.Embeddings
  alias YouCongress.Likes
  alias YouCongress.Opinions.ContentEmbedding
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Workers.UpdateAuthorPublicFigureWorker
  alias YouCongress.Workers.UpdateOpinionDescendantsCountWorker
  alias YouCongress.Workers.SyncStatementOpinionsCountWorker
  alias YouCongress.Workers.VerificationWorker

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

  def get_opinion(opts) when is_list(opts),
    do: opts |> Keyword.put_new(:limit, 1) |> build_query() |> Repo.one()

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
  Returns sourced quotes ordered by content embedding cosine similarity.

  Each returned opinion has its `:similarity` virtual field populated with the
  cosine similarity (1.0 - cosine distance) to the query text.
  """
  def get_by_content_similarity(text) when is_binary(text) do
    if String.trim(text) == "" do
      []
    else
      case Embeddings.embed(text) do
        {:ok, embedding} when is_list(embedding) ->
          query_embedding = Pgvector.new(embedding)

          from(o in Opinion,
            where: not is_nil(o.source_url) and not is_nil(o.content_embedding),
            order_by: cosine_distance(o.content_embedding, ^query_embedding),
            limit: 100,
            select_merge: %{
              similarity: 1.0 - cosine_distance(o.content_embedding, ^query_embedding)
            }
          )
          |> Repo.all()

        _ ->
          []
      end
    end
  end

  def get_by_content_similarity(_text), do: []

  @doc """
  Creates a opinion.

  ## Examples

      iex> create_opinion(%{field: value})
      {:ok, %Opinion{}}

      iex> create_opinion(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_opinion(attrs \\ %{}) do
    attrs = ContentEmbedding.put(attrs, %Opinion{})

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:opinion, Opinion.changeset(%Opinion{}, attrs))
      |> enqueue_update_ancestor_counts(attrs["ancestry"])
      |> maybe_enqueue_update_author_public_figure(attrs)
      |> Repo.transaction()

    maybe_enqueue_quote_verification(result)
    result
  end

  # A quote (an opinion with a source_url) is AI-verified whenever it is created.
  defp maybe_enqueue_quote_verification(
         {:ok, %{opinion: %Opinion{source_url: source_url, id: id}}}
       )
       when not is_nil(source_url) do
    enqueue_quote_verification(id)
  end

  defp maybe_enqueue_quote_verification(_), do: :ok

  defp enqueue_quote_verification(opinion_id) do
    %{"subject" => "quote", "id" => opinion_id}
    |> VerificationWorker.new()
    |> Oban.insert()
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

  defp maybe_enqueue_update_author_public_figure(multi, attrs) do
    author_id = attrs["author_id"] || attrs[:author_id]
    source_url = attrs["source_url"] || attrs[:source_url]

    if author_id && source_url do
      Ecto.Multi.insert(
        multi,
        :update_author_public_figure,
        UpdateAuthorPublicFigureWorker.new(%{"author_id" => author_id})
      )
    else
      multi
    end
  end

  defp enqueue_sync_opinions_count(multi, []), do: multi

  defp enqueue_sync_opinions_count(multi, statement_ids) do
    Enum.reduce(statement_ids, multi, fn statement_id, multi ->
      Ecto.Multi.insert(
        multi,
        "sync_opinions_count_#{statement_id}",
        SyncStatementOpinionsCountWorker.new(%{"statement_id" => statement_id})
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
    attrs = ContentEmbedding.put(attrs, opinion)
    changeset = Opinion.changeset(opinion, attrs)
    result = Repo.update(changeset)
    maybe_reverify_quote_on_update(result, changeset)
    result
  end

  # Re-verify a quote only when its content or source changed (not on count-only updates).
  defp maybe_reverify_quote_on_update({:ok, %Opinion{source_url: source_url, id: id}}, changeset)
       when not is_nil(source_url) do
    if Map.has_key?(changeset.changes, :content) or Map.has_key?(changeset.changes, :source_url) do
      enqueue_quote_verification(id)
    end

    :ok
  end

  defp maybe_reverify_quote_on_update(_result, _changeset), do: :ok

  @doc """
  Deletes a opinion.

  ## Examples

      iex> delete_opinion(opinion)
      {:ok, %Opinion{}}

      iex> delete_opinion(opinion)
      {:error, %Ecto.Changeset{}}

  """
  def delete_opinion(%Opinion{} = opinion) do
    # Get affected statement IDs before deletion
    statement_ids =
      from(os in "opinions_statements",
        where: os.opinion_id == ^opinion.id,
        select: os.statement_id,
        distinct: true
      )
      |> Repo.all()

    Ecto.Multi.new()
    |> maybe_delete_inferred_quote_votes(opinion, statement_ids)
    |> Ecto.Multi.delete(:opinion, opinion)
    |> enqueue_update_ancestor_counts(opinion.ancestry)
    |> enqueue_sync_opinions_count(statement_ids)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  defp maybe_delete_inferred_quote_votes(multi, %Opinion{source_url: nil}, _statement_ids),
    do: multi

  defp maybe_delete_inferred_quote_votes(multi, %Opinion{author_id: nil}, _statement_ids),
    do: multi

  defp maybe_delete_inferred_quote_votes(multi, _opinion, []), do: multi

  defp maybe_delete_inferred_quote_votes(
         multi,
         %Opinion{id: opinion_id, author_id: author_id},
         statement_ids
       ) do
    Ecto.Multi.run(multi, :inferred_quote_votes, fn _repo, _changes ->
      votes =
        from(v in Vote,
          where:
            v.author_id == ^author_id and v.statement_id in ^statement_ids and
              v.opinion_id == ^opinion_id
        )
        |> Repo.all()

      reassign_or_delete_current_quote_votes(votes, author_id, opinion_id)
    end)
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

  def list_sourced_statement_opinions_by_author(_statement_id, []), do: %{}

  def list_sourced_statement_opinions_by_author(statement_id, author_ids)
      when is_integer(statement_id) and is_list(author_ids) do
    author_ids = Enum.reject(author_ids, &is_nil/1)

    from(o in Opinion,
      join: os in "opinions_statements",
      on: os.opinion_id == o.id,
      where:
        os.statement_id == ^statement_id and o.author_id in ^author_ids and
          not is_nil(o.source_url),
      order_by: [fragment("? DESC NULLS LAST", o.year), desc: o.id],
      preload: [:author]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.author_id)
  end

  def list_sourced_statement_opinions_by_statement_and_author(statement_ids, author_ids)
      when is_list(statement_ids) and is_list(author_ids) do
    statement_ids = statement_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()
    author_ids = author_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if statement_ids == [] or author_ids == [] do
      %{}
    else
      from(o in Opinion,
        join: os in "opinions_statements",
        on: os.opinion_id == o.id,
        where:
          os.statement_id in ^statement_ids and o.author_id in ^author_ids and
            not is_nil(o.source_url),
        order_by: [
          asc: os.statement_id,
          asc: o.author_id,
          desc_nulls_last: o.year,
          desc: o.id
        ],
        preload: [:author],
        select: {os.statement_id, o}
      )
      |> Repo.all()
      |> Enum.group_by(
        fn {statement_id, opinion} -> {statement_id, opinion.author_id} end,
        fn {_statement_id, opinion} -> opinion end
      )
    end
  end

  defp build_query(opts) do
    base_query = from(o in Opinion)

    Enum.reduce(opts, base_query, fn
      {:ids, ids}, query ->
        from q in query, where: q.id in ^ids

      {:exclude_ids, exclude_ids}, query ->
        from q in query, where: q.id not in ^exclude_ids

      {:id_less_than, id}, query ->
        from q in query, where: q.id < ^id

      {:id_greater_than, id}, query ->
        from q in query, where: q.id > ^id

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
          where:
            fragment(
              "EXISTS (SELECT 1 FROM opinions_statements os WHERE os.opinion_id = ?)",
              q.id
            )

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

      {:exclude_source_prefixes, prefixes}, query ->
        prefixes
        |> List.wrap()
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(query, fn prefix, query_acc ->
          pattern = "#{prefix}%"

          from q in query_acc,
            where: is_nil(q.source_url) or not ilike(q.source_url, ^pattern)
        end)

      {:twin, twin_value}, query ->
        from q in query, where: q.twin == ^twin_value

      {:include_twins, include_twins}, query ->
        from q in query, where: q.twin == ^include_twins or q.twin == false

      {:is_verified, true}, query ->
        from q in query, where: not is_nil(q.verification_status)

      {:is_verified, false}, query ->
        from q in query, where: is_nil(q.verification_status)

      {:needs_verification, true}, query ->
        # Any of the three dimensions still pending: the quote's own authenticity,
        # the relevance of any of its statement links, or any of its votes' answers.
        from q in query,
          where:
            is_nil(q.verification_status) or
              fragment(
                "EXISTS (SELECT 1 FROM opinions_statements os WHERE os.opinion_id = ? AND os.verification_status IS NULL)",
                q.id
              ) or
              fragment(
                "EXISTS (SELECT 1 FROM votes v WHERE v.opinion_id = ? AND v.verification_status IS NULL)",
                q.id
              )

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

    # Get affected statement IDs before deletion
    statement_ids =
      from(os in "opinions_statements",
        where: os.opinion_id in ^subtree_ids,
        select: os.statement_id,
        distinct: true
      )
      |> Repo.all()

    result = Repo.delete_all(from o in Opinion, where: o.id in ^subtree_ids)

    Ecto.Multi.new()
    |> enqueue_update_ancestor_counts(opinion.ancestry)
    |> enqueue_sync_opinions_count(statement_ids)
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

  def count(opts \\ []) do
    opts
    |> build_query()
    |> exclude(:preload)
    |> exclude(:order_by)
    |> exclude(:limit)
    |> exclude(:offset)
    |> Repo.aggregate(:count, :id)
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
    with :ok <- ensure_not_already_associated(opinion.id, statement.id) do
      opinion_statement_changeset =
        OpinionStatement.changeset(%OpinionStatement{}, %{
          opinion_id: opinion.id,
          statement_id: statement.id,
          user_id: user_id
        })

      result =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:opinion_statement, opinion_statement_changeset)
        |> Ecto.Multi.insert(
          :sync_opinions_count,
          SyncStatementOpinionsCountWorker.new(%{"statement_id" => statement.id})
        )
        |> maybe_update_current_quote_vote(opinion, statement)
        |> Repo.transaction()

      case result do
        {:ok, _} ->
          {:ok, Repo.preload(opinion, :statements)}

        {:error, :opinion_statement, changeset, _} ->
          {:error, changeset}

        {:error, _, _, _} ->
          {:error, :transaction_failed}
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

  defp ensure_not_already_associated(opinion_id, statement_id) do
    case Repo.get_by(OpinionStatement, opinion_id: opinion_id, statement_id: statement_id) do
      nil -> :ok
      _ -> {:error, :already_associated}
    end
  end

  def remove_opinion_from_statement(%Opinion{} = opinion, statement_id)
      when is_integer(statement_id) do
    statement = YouCongress.Statements.get_statement!(statement_id)
    remove_opinion_from_statement(opinion, statement)
  end

  def remove_opinion_from_statement(
        %Opinion{} = opinion,
        %YouCongress.Statements.Statement{} = statement
      ) do
    case Repo.get_by(OpinionStatement,
           opinion_id: opinion.id,
           statement_id: statement.id
         ) do
      nil ->
        {:error, :not_associated}

      %OpinionStatement{} = opinion_statement ->
        result =
          Ecto.Multi.new()
          |> Ecto.Multi.delete(:opinion_statement, opinion_statement)
          |> Ecto.Multi.insert(
            :sync_opinions_count,
            SyncStatementOpinionsCountWorker.new(%{"statement_id" => statement.id})
          )
          |> maybe_reassign_or_delete_current_quote_vote(opinion, statement)
          |> Repo.transaction()

        case result do
          {:ok, _} ->
            {:ok, Repo.preload(opinion, :statements)}

          {:error, :opinion_statement, changeset, _} ->
            {:error, changeset}

          {:error, _, _, _} ->
            {:error, :transaction_failed}
        end
    end
  end

  defp maybe_update_current_quote_vote(
         multi,
         %Opinion{source_url: source_url, author_id: author_id} = opinion,
         statement
       )
       when not is_nil(source_url) and not is_nil(author_id) do
    Ecto.Multi.run(multi, :current_quote_vote, fn _repo, _changes ->
      case Votes.get_by(%{author_id: author_id, statement_id: statement.id}) do
        nil -> {:ok, nil}
        vote -> Votes.update_vote(vote, %{opinion_id: opinion.id, twin: false})
      end
    end)
  end

  defp maybe_update_current_quote_vote(multi, _opinion, _statement), do: multi

  defp maybe_reassign_or_delete_current_quote_vote(
         multi,
         %Opinion{source_url: source_url, author_id: author_id} = opinion,
         statement
       )
       when not is_nil(source_url) and not is_nil(author_id) do
    Ecto.Multi.run(multi, :current_quote_vote, fn _repo, _changes ->
      case Votes.get_by(%{
             author_id: author_id,
             statement_id: statement.id,
             opinion_id: opinion.id
           }) do
        nil ->
          {:ok, nil}

        vote ->
          reassign_or_delete_current_quote_votes([vote], author_id, opinion.id)
      end
    end)
  end

  defp maybe_reassign_or_delete_current_quote_vote(multi, _opinion, _statement), do: multi

  defp reassign_or_delete_current_quote_votes(votes, author_id, removed_opinion_id) do
    Enum.reduce_while(votes, {:ok, []}, fn vote, {:ok, changed_votes} ->
      case next_sourced_statement_opinion(vote.statement_id, author_id, removed_opinion_id) do
        %Opinion{} = replacement ->
          case Votes.update_vote(vote, %{opinion_id: replacement.id, twin: false}) do
            {:ok, updated_vote} -> {:cont, {:ok, [updated_vote | changed_votes]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        nil ->
          case Votes.delete_vote(vote) do
            {:ok, deleted_vote} -> {:cont, {:ok, [deleted_vote | changed_votes]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp next_sourced_statement_opinion(statement_id, author_id, removed_opinion_id) do
    from(o in Opinion,
      join: os in "opinions_statements",
      on: os.opinion_id == o.id,
      where:
        os.statement_id == ^statement_id and o.author_id == ^author_id and
          o.id != ^removed_opinion_id and not is_nil(o.source_url),
      order_by: [fragment("? DESC NULLS LAST", o.year), desc: o.id],
      limit: 1
    )
    |> Repo.one()
  end
end
