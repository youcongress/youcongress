defmodule YouCongress.Authors.MergeRepair do
  @moduledoc """
  One-off repair for data orphaned by `Authors.merge_authors/2`.

  A vote holds a single `opinion_id`, but a vote is unique per `(author,
  statement)`. When two authors that both voted on the same statement were
  merged, their two votes were collapsed into one, leaving every opinion the
  surviving vote no longer pointed at orphaned: still attributed to the
  survivor, but referenced by no vote, so it never appeared on the profile.

  This module re-links those orphaned sourced opinions so they resurface as
  alternate opinions:

    1. Re-create the `opinions_statements` link for any sourced opinion that is
       still referenced by a vote but lost its join row.
    2. Repoint each surviving vote whose opinion is missing or unsourced to the
       best sourced opinion the author has on that statement, so the vote counts
       as a sourced-opinion vote and the alternates are surfaced.

  Run from a console with `YouCongress.Authors.MergeRepair.repair/0`.
  """

  import Ecto.Query

  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote

  @doc """
  Runs both repair steps and returns a report of how many rows were touched.
  """
  @spec repair() :: %{linked: non_neg_integer(), repointed: non_neg_integer()}
  def repair do
    %{
      linked: relink_sourced_opinions(),
      repointed: repoint_unsourced_votes()
    }
  end

  # Step 1 — recover opinions_statements rows for sourced opinions that are still
  # referenced by a vote but lost their join row during a merge.
  defp relink_sourced_opinions do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      from(v in Vote,
        join: o in Opinion,
        on: o.id == v.opinion_id,
        left_join: os in OpinionStatement,
        on: os.opinion_id == o.id and os.statement_id == v.statement_id,
        where: not is_nil(o.source_url) and is_nil(os.id),
        distinct: true,
        select: %{
          opinion_id: o.id,
          statement_id: v.statement_id,
          user_id: o.user_id,
          verification_status: o.verification_status
        }
      )
      |> Repo.all()
      |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))

    case rows do
      [] ->
        0

      rows ->
        {count, _} =
          Repo.insert_all(OpinionStatement, rows,
            on_conflict: :nothing,
            conflict_target: [:opinion_id, :statement_id]
          )

        count
    end
  end

  # Step 2 — repoint surviving votes whose opinion is missing or unsourced to the
  # best sourced opinion the author has on that statement (via opinions_statements).
  defp repoint_unsourced_votes do
    candidates()
    |> Enum.reduce(0, fn vote, count ->
      case best_sourced_opinion_id(vote.author_id, vote.statement_id) do
        nil ->
          count

        opinion_id when opinion_id == vote.opinion_id ->
          count

        opinion_id ->
          {updated, _} =
            from(v in Vote, where: v.id == ^vote.id)
            |> Repo.update_all(set: [opinion_id: opinion_id])

          count + updated
      end
    end)
  end

  defp candidates do
    from(v in Vote,
      left_join: o in Opinion,
      on: o.id == v.opinion_id,
      join: os in OpinionStatement,
      on: os.statement_id == v.statement_id,
      join: so in Opinion,
      on: so.id == os.opinion_id,
      where:
        (is_nil(v.opinion_id) or is_nil(o.source_url)) and so.author_id == v.author_id and
          not is_nil(so.source_url),
      distinct: true,
      select: %{
        id: v.id,
        author_id: v.author_id,
        statement_id: v.statement_id,
        opinion_id: v.opinion_id
      }
    )
    |> Repo.all()
  end

  defp best_sourced_opinion_id(author_id, statement_id) do
    from(o in Opinion,
      join: os in OpinionStatement,
      on: os.opinion_id == o.id,
      where:
        os.statement_id == ^statement_id and o.author_id == ^author_id and
          not is_nil(o.source_url),
      order_by: [
        desc:
          fragment(
            "CASE WHEN ? IN ('verified', 'ai_verified', 'endorsed') THEN 1 ELSE 0 END",
            o.verification_status
          ),
        desc_nulls_last: o.date,
        desc: o.id
      ],
      limit: 1,
      select: o.id
    )
    |> Repo.one()
  end
end
