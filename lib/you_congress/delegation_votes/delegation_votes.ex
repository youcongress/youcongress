defmodule YouCongress.DelegationVotes do
  @moduledoc "Materializes council decisions, keeping a compatible votes read projection."
  import Ecto.Query
  alias YouCongress.{Repo, Councils}
  alias YouCongress.Councils.{Council, Decision}
  alias YouCongress.Votes.Vote
  alias YouCongress.Workers.RefreshAuthorStatementDelegatedVotesWorker

  def update_author_delegated_votes(author_id) do
    {:ok, _} = Councils.ensure(author_id)
    ids = [author_id | Councils.delegate_ids(author_id)]

    statement_ids =
      Repo.all(from v in Vote, where: v.author_id in ^ids, select: v.statement_id, distinct: true)

    old_ids =
      Repo.all(from d in Decision, where: d.author_id == ^author_id, select: d.statement_id)

    Enum.each(
      Enum.uniq(statement_ids ++ old_ids),
      &update_author_statement_delegated_votes(author_id, &1)
    )

    :ok
  end

  def update_delegated_votes(%{deleguee_id: id}), do: update_author_delegated_votes(id)

  def update_author_statement_delegated_votes(%{author_id: a, statement_id: s}),
    do: update_author_statement_delegated_votes(a, s)

  def update_author_statement_delegated_votes(author_id, statement_id) do
    {:ok, _} = Councils.ensure(author_id)

    {:ok, result} =
      Repo.transaction(fn ->
        Repo.one!(from c in Council, where: c.author_id == ^author_id, lock: "FOR UPDATE")
        explanation = Councils.explain(author_id, statement_id)
        previous = Repo.get_by(Decision, author_id: author_id, statement_id: statement_id)

        attrs = %{
          author_id: author_id,
          statement_id: statement_id,
          answer: explanation.answer && to_string(explanation.answer),
          council_version: explanation.version,
          explanation: Jason.decode!(Jason.encode!(explanation))
        }

        (previous || %Decision{}) |> Decision.changeset(attrs) |> Repo.insert_or_update!()
        project(author_id, statement_id, explanation.answer)

        if previous && previous.answer != attrs.answer do
          YouCongress.TrustNetwork.notify(
            author_id,
            "decision:#{statement_id}:#{System.unique_integer([:positive])}",
            "Your council's position changed. Inspect the updated evidence.",
            "/council?statement=#{statement_id}"
          )
        end

        if explanation.direct, do: :direct_vote_exists, else: :ok
      end)

    result
  end

  # Conditional writes protect a concurrently cast direct vote. Canonical direct/source
  # rows are never overwritten by the compatibility projection.
  defp project(author_id, statement_id, nil) do
    Repo.delete_all(
      from v in Vote,
        where: v.author_id == ^author_id and v.statement_id == ^statement_id and not v.direct
    )
  end

  defp project(author_id, statement_id, answer) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    conflict =
      from v in Vote,
        where: not v.direct,
        update: [set: [answer: ^answer, origin: "delegated", updated_at: ^now]]

    Repo.insert_all(
      Vote,
      [
        %{
          author_id: author_id,
          statement_id: statement_id,
          answer: answer,
          direct: false,
          twin: false,
          origin: "delegated",
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:author_id, :statement_id],
      on_conflict: conflict
    )
  end

  def enqueue_deleguees_for_delegate_statement(delegate_id, statement_id) do
    legacy =
      Repo.all(
        from d in YouCongress.Delegations.Delegation,
          where: d.delegate_id == ^delegate_id,
          select: d.deleguee_id
      )

    Enum.each(Enum.uniq(Councils.followers(delegate_id) ++ legacy), fn id ->
      # Invalidate before asynchronous refresh; never leave a stale counted result.
      Repo.delete_all(
        from v in Vote,
          where: v.author_id == ^id and v.statement_id == ^statement_id and not v.direct
      )

      Repo.delete_all(
        from d in Decision, where: d.author_id == ^id and d.statement_id == ^statement_id
      )

      YouCongress.TrustNetwork.notify(
        id,
        evidence_notice_key(delegate_id, statement_id),
        "Evidence or a position from one of your council members changed.",
        "/council?statement=#{statement_id}"
      )

      %{author_id: id, statement_id: statement_id}
      |> RefreshAuthorStatementDelegatedVotesWorker.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp evidence_notice_key(author_id, statement_id) do
    vote = Repo.get_by(Vote, author_id: author_id, statement_id: statement_id)

    opinion =
      if vote && vote.opinion_id, do: Repo.get(YouCongress.Opinions.Opinion, vote.opinion_id)

    state =
      {vote && {vote.id, vote.revision, vote.answer, vote.verification_status},
       opinion && {opinion.id, opinion.evidence_revision, opinion.verification_status}}

    hash = :crypto.hash(:sha256, :erlang.term_to_binary(state)) |> Base.encode16(case: :lower)
    "evidence:#{author_id}:#{statement_id}:#{hash}"
  end

  def refresh_opinion(opinion_id) do
    Repo.all(from v in Vote, where: v.opinion_id == ^opinion_id)
    |> Enum.each(&enqueue_deleguees_for_delegate_statement(&1.author_id, &1.statement_id))

    :ok
  end
end
