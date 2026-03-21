defmodule YouCongress.Statements.StatementQueries do
  @moduledoc """
  Provides query functions for retrieving statement-related data from the database.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votes.Vote
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.OpinionCard

  @doc """
  Returns one vote per statement, prioritizing:
  1. Current user's vote (if logged in)
  2. Votes from top authors (if provided)
  3. Votes from wikipedia authors (if provided)
  4. Most recent votes
  """
  def get_one_vote_per_statement(statement_ids, current_user \\ nil, opts \\ []) do
    top_author_ids = Keyword.get(opts, :top_author_ids, [])
    wikipedia_author_ids = Keyword.get(opts, :wikipedia_author_ids, [])

    base_query =
      from(v in Vote,
        join: o in assoc(v, :opinion),
        where: v.statement_id in ^statement_ids and not is_nil(v.opinion_id),
        preload: [:author, :opinion]
      )

    query =
      cond do
        current_user && (top_author_ids != [] || wikipedia_author_ids != []) ->
          from([v, o] in base_query,
            order_by: [
              desc:
                fragment(
                  "CASE WHEN ? = ? THEN 3 WHEN ? = ANY(?) THEN 2 WHEN ? = ANY(?) THEN 1 ELSE 0 END",
                  v.author_id,
                  ^current_user.author_id,
                  v.author_id,
                  ^top_author_ids,
                  v.author_id,
                  ^wikipedia_author_ids
                ),
              desc: v.inserted_at
            ],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )

        current_user ->
          from([v, o] in base_query,
            order_by: [
              desc:
                fragment(
                  "CASE WHEN ? = ? THEN 1 ELSE 0 END",
                  v.author_id,
                  ^current_user.author_id
                ),
              desc: v.inserted_at
            ],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )

        top_author_ids != [] || wikipedia_author_ids != [] ->
          from([v, o] in base_query,
            order_by: [
              desc:
                fragment(
                  "CASE WHEN ? = ANY(?) THEN 2 WHEN ? = ANY(?) THEN 1 ELSE 0 END",
                  v.author_id,
                  ^top_author_ids,
                  v.author_id,
                  ^wikipedia_author_ids
                ),
              desc: v.inserted_at
            ],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )

        true ->
          from([v, o] in base_query,
            order_by: [desc: v.inserted_at],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )
      end

    query
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Returns opinion cards in round-robin order across all statements.

  Round-robin ordering ensures each statement appears once before any statement repeats:
  - Round 1: statement1+opinion1, statement2+opinion1, statement3+opinion1...
  - Round 2: statement1+opinion2, statement2+opinion2... (only statements with 2+ opinions)
  - Continue until all opinions exhausted

  It should display first opinions from top authors, then from wikipedia authors, then from other authors.

  Options:
  - :hall_name - filter by hall (default "all")
  - :top_author_ids - IDs of top authors for prioritization
  - :wikipedia_author_ids - IDs of wikipedia authors for secondary prioritization
  - :wikipedia_only - restrict results to authors with a wikipedia_url (default false)
  - :offset - number of cards to skip
  - :limit - max cards to return
  """
  def get_opinion_cards_round_robin(opts \\ []) do
    hall_name = Keyword.get(opts, :hall_name, "all")
    top_author_ids = Keyword.get(opts, :top_author_ids, [])
    wikipedia_author_ids = Keyword.get(opts, :wikipedia_author_ids, [])
    wikipedia_only = Keyword.get(opts, :wikipedia_only, false)
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 15)

    # Track which features we actually use
    has_hall = hall_name != "all"
    has_top = top_author_ids != []
    # Only use wikipedia if we also have top authors (for the priority ordering to make sense)
    has_wiki = has_top && wikipedia_author_ids != []

    # Build params list and SQL fragments together to keep them in sync
    # Start with param index 1
    param_idx = 1

    # Hall filter
    {hall_filter, params, param_idx} =
      if has_hall do
        {"JOIN halls_statements hs ON hs.statement_id = v.statement_id
         JOIN halls h ON h.id = hs.hall_id AND h.name = $#{param_idx}", [hall_name],
         param_idx + 1}
      else
        {"", [], param_idx}
      end

    {author_join, author_filter} =
      if wikipedia_only do
        {"JOIN authors a ON a.id = v.author_id", "AND a.wikipedia_url IS NOT NULL"}
      else
        {"", ""}
      end

    # Priority expression with author params
    {priority_expr, params, param_idx} =
      cond do
        has_top && has_wiki ->
          expr =
            "(CASE WHEN v.author_id = ANY($#{param_idx}) THEN 20000000000 WHEN v.author_id = ANY($#{param_idx + 1}) THEN 10000000000 ELSE 0 END) + EXTRACT(EPOCH FROM v.inserted_at)"

          {expr, params ++ [top_author_ids, wikipedia_author_ids], param_idx + 2}

        has_top ->
          expr =
            "(CASE WHEN v.author_id = ANY($#{param_idx}) THEN 20000000000 ELSE 0 END) + EXTRACT(EPOCH FROM v.inserted_at)"

          {expr, params ++ [top_author_ids], param_idx + 1}

        true ->
          {"EXTRACT(EPOCH FROM v.inserted_at)", params, param_idx}
      end

    # Add offset and limit params
    offset_param = "$#{param_idx}"
    limit_param = "$#{param_idx + 1}"
    params = params ++ [offset, limit]

    sql = """
    WITH ranked_votes AS (
      SELECT
        v.id as vote_id,
        v.statement_id,
        s.updated_at as statement_updated_at,
        #{priority_expr} as priority,
        ROW_NUMBER() OVER (
          PARTITION BY v.statement_id
          ORDER BY #{priority_expr} DESC
        ) as round_number
      FROM votes v
      JOIN opinions o ON o.id = v.opinion_id
      JOIN statements s ON s.id = v.statement_id
      #{hall_filter}
      #{author_join}
      WHERE v.opinion_id IS NOT NULL
      #{author_filter}
    )
    SELECT rv.vote_id, rv.statement_id, rv.round_number
    FROM ranked_votes rv
    ORDER BY rv.round_number ASC, rv.priority DESC, rv.statement_updated_at DESC
    OFFSET #{offset_param}
    LIMIT #{limit_param}
    """

    result = Repo.query!(sql, params)

    if result.rows == [] do
      []
    else
      # Parse results
      results =
        Enum.map(result.rows, fn [vote_id, statement_id, round_number] ->
          %{vote_id: vote_id, statement_id: statement_id, round_number: round_number}
        end)

      vote_ids = Enum.map(results, & &1.vote_id)
      statement_ids = results |> Enum.map(& &1.statement_id) |> Enum.uniq()

      # Load votes with preloads
      votes =
        from(v in Vote,
          where: v.id in ^vote_ids,
          preload: [:author, :opinion]
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      # Load statements
      statements =
        from(s in Statement,
          where: s.id in ^statement_ids
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      # Build opinion cards in the correct order
      Enum.map(results, fn %{vote_id: vote_id, statement_id: statement_id, round_number: round} ->
        vote = Map.get(votes, vote_id)
        statement = Map.get(statements, statement_id)

        %OpinionCard{
          id: "card-#{statement_id}-#{vote_id}",
          statement: statement,
          vote: vote,
          round: round
        }
      end)
    end
  end

  @doc """
  Returns one opinion card per statement showing the opinion with the most likes.

  Statements are ordered by total opinion_likes_count (descending) so the most
  popular statements appear first. Within each statement the opinion is chosen
  by likes_count (ties fall back to the most recently updated opinion/vote).

  Options:
  - :hall_name - filter by hall (default "all")
  - :offset - number of cards to skip
  - :limit - max cards to return
  """
  def get_opinion_cards_by_top_likes(opts \\ []) do
    hall_name = Keyword.get(opts, :hall_name, "all")
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 15)

    has_hall = hall_name != "all"

    {hall_filter, params, param_idx} =
      if has_hall do
        {"JOIN halls_statements hs ON hs.statement_id = s.id\n         JOIN halls h ON h.id = hs.hall_id AND h.name = $1", [hall_name], 2}
      else
        {"", [], 1}
      end

    offset_param = "$#{param_idx}"
    limit_param = "$#{param_idx + 1}"
    params = params ++ [offset, limit]

    sql = """
    WITH ranked_votes AS (
      SELECT
        v.id as vote_id,
        s.id as statement_id,
        s.opinion_likes_count,
        s.inserted_at as statement_inserted_at,
        ROW_NUMBER() OVER (
          PARTITION BY s.id
          ORDER BY o.likes_count DESC, o.updated_at DESC, v.inserted_at DESC
        ) as vote_rank
      FROM statements s
      JOIN votes v ON v.statement_id = s.id
      JOIN opinions o ON o.id = v.opinion_id
      JOIN authors a ON a.id = v.author_id
      #{hall_filter}
      WHERE v.opinion_id IS NOT NULL
        AND a.wikipedia_url IS NOT NULL
    )
    SELECT rv.vote_id, rv.statement_id
    FROM ranked_votes rv
    WHERE rv.vote_rank = 1
    ORDER BY rv.opinion_likes_count DESC, rv.statement_inserted_at DESC
    OFFSET #{offset_param}
    LIMIT #{limit_param}
    """

    result = Repo.query!(sql, params)

    if result.rows == [] do
      []
    else
      results =
        Enum.map(result.rows, fn [vote_id, statement_id] ->
          %{vote_id: vote_id, statement_id: statement_id}
        end)

      vote_ids = Enum.map(results, & &1.vote_id)
      statement_ids = results |> Enum.map(& &1.statement_id) |> Enum.uniq()

      votes =
        from(v in Vote,
          where: v.id in ^vote_ids,
          preload: [:author, :opinion]
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      statements =
        from(s in Statement,
          where: s.id in ^statement_ids
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      Enum.map(results, fn %{vote_id: vote_id, statement_id: statement_id} ->
        vote = Map.get(votes, vote_id)
        statement = Map.get(statements, statement_id)

        %OpinionCard{
          id: "card-#{statement_id}-#{vote_id}",
          statement: statement,
          vote: vote,
          round: 1
        }
      end)
    end
  end

  @doc """
  Returns opinion cards ordered by most recently updated opinions first.

  Unlike round-robin, statements can appear consecutively if they have
  the most recent opinions.

  Options:
  - :hall_name - filter by hall (default "all")
  - :offset - number of cards to skip
  - :limit - max cards to return
  """
  def get_opinion_cards_by_recency(opts \\ []) do
    hall_name = Keyword.get(opts, :hall_name, "all")
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 15)

    has_hall = hall_name != "all"

    # Build params and hall filter
    {hall_filter, params, param_idx} =
      if has_hall do
        {"JOIN halls_statements hs ON hs.statement_id = v.statement_id
         JOIN halls h ON h.id = hs.hall_id AND h.name = $1", [hall_name], 2}
      else
        {"", [], 1}
      end

    offset_param = "$#{param_idx}"
    limit_param = "$#{param_idx + 1}"
    params = params ++ [offset, limit]

    sql = """
    SELECT v.id as vote_id, v.statement_id, o.updated_at as opinion_updated_at
    FROM votes v
    JOIN opinions o ON o.id = v.opinion_id
    JOIN statements s ON s.id = v.statement_id
    #{hall_filter}
    WHERE v.opinion_id IS NOT NULL
    ORDER BY o.updated_at DESC
    OFFSET #{offset_param}
    LIMIT #{limit_param}
    """

    result = Repo.query!(sql, params)

    if result.rows == [] do
      []
    else
      results =
        Enum.map(result.rows, fn [vote_id, statement_id, _opinion_updated_at] ->
          %{vote_id: vote_id, statement_id: statement_id}
        end)

      vote_ids = Enum.map(results, & &1.vote_id)
      statement_ids = results |> Enum.map(& &1.statement_id) |> Enum.uniq()

      # Load votes with preloads
      votes =
        from(v in Vote,
          where: v.id in ^vote_ids,
          preload: [:author, :opinion]
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      # Load statements
      statements =
        from(s in Statement,
          where: s.id in ^statement_ids
        )
        |> Repo.all()
        |> Map.new(&{&1.id, &1})

      # Build opinion cards in the correct order (by recency)
      Enum.map(results, fn %{vote_id: vote_id, statement_id: statement_id} ->
        vote = Map.get(votes, vote_id)
        statement = Map.get(statements, statement_id)

        %OpinionCard{
          id: "card-#{statement_id}-#{vote_id}",
          statement: statement,
          vote: vote,
          round: 1
        }
      end)
    end
  end
end
