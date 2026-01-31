defmodule YouCongress.Statements.StatementQueries do
  @moduledoc """
  Provides query functions for retrieving statement-related data from the database.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votes.Vote

  @doc """
  Returns one vote per statement, prioritizing:
  1. Current user's vote (if logged in)
  2. Votes from top authors (if provided)
  3. Votes from wikipedia authors (if provided)
  4. Votes with highest opinion likes_count
  5. Most recent votes
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
              desc: o.likes_count,
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
              desc: o.likes_count,
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
              desc: o.likes_count,
              desc: v.inserted_at
            ],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )

        true ->
          from([v, o] in base_query,
            order_by: [desc: o.likes_count, desc: v.inserted_at],
            distinct: [v.statement_id],
            select: {v.statement_id, v}
          )
      end

    query
    |> Repo.all()
    |> Enum.into(%{})
  end
end
