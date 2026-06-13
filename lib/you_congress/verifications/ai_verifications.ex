defmodule YouCongress.Verifications.AIVerifications do
  @moduledoc """
  Turns a completed LLM verification result into a stored verification and drives
  the next stage of the pipeline.

  Cascade:
  - `quote` positive  -> verify the relevance of each of the quote's statement links.
  - `relevance` positive -> verify each vote that cites the quote on that statement.
  - `relevance` disputed -> unlink the quote from the statement.
  - `vote` -> set the vote's answer to whichever of for/against/abstain the quote
    actually supports (if any) and mark it ai_verified; otherwise mark it
    ai_unverifiable.

  All verifications are owned by the configured `:verification_user_id`
  (an admin/moderator). When it is unset, this module logs and no-ops so dev and
  tests never crash.
  """

  import Ecto.Query, warn: false

  require Logger

  alias YouCongress.Repo
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Statements
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Verifications
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.VoteVerifications
  alias YouCongress.VerificationStatus
  alias YouCongress.Workers.VerificationWorker

  @allowed_statuses ~w(ai_verified ai_unverifiable disputed unverifiable unverified)
  @status_aliases %{"verified" => "ai_verified"}
  @answers ~w(for against abstain)

  @doc """
  Record the verification for `subject`/`id` from a completed LLM `result` and
  cascade to the next stage. `subject` is `"quote"`, `"relevance"` or `"vote"`.
  """
  @spec record_and_cascade(String.t(), integer(), map()) :: :ok
  def record_and_cascade(subject, id, result) do
    case system_user_id() do
      nil ->
        Logger.warning(
          "verification_user_id not configured; skipping #{subject} verification for ##{id}"
        )

        :ok

      user_id ->
        do_record(subject, id, result, model(result), user_id)
    end
  end

  defp do_record("quote", opinion_id, result, model, user_id) do
    status = normalize_status(result["status"])

    attrs = %{
      opinion_id: opinion_id,
      status: status,
      comment: comment(result),
      model: model,
      user_id: user_id
    }

    case Verifications.create_verification(attrs) do
      {:ok, _} ->
        if VerificationStatus.positive?(status), do: enqueue_relevance(opinion_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to record quote verification for ##{opinion_id}: #{inspect(reason)}")
        :ok
    end
  end

  defp do_record("relevance", opinion_statement_id, result, model, user_id) do
    status = normalize_status(result["status"])

    case Repo.get(OpinionStatement, opinion_statement_id) do
      nil ->
        :ok

      %OpinionStatement{} = opinion_statement when status == :disputed ->
        # A disputed relevance means the quote does not back this statement: unlink it.
        Logger.info(
          "Unlinking opinion #{opinion_statement.opinion_id} from statement " <>
            "#{opinion_statement.statement_id}: #{comment(result)}"
        )

        unlink(opinion_statement)

      %OpinionStatement{} = opinion_statement ->
        attrs = %{
          opinion_statement_id: opinion_statement_id,
          status: status,
          comment: comment(result),
          model: model,
          user_id: user_id
        }

        case OpinionStatementVerifications.create_verification(attrs) do
          {:ok, _} ->
            if VerificationStatus.positive?(status), do: enqueue_votes(opinion_statement)
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to record relevance verification for ##{opinion_statement_id}: #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  defp do_record("vote", vote_id, result, model, user_id) do
    case Repo.get(Vote, vote_id) do
      nil ->
        :ok

      %Vote{} = vote ->
        correct_answer = normalize_answer(result["correct_answer"])

        attrs = %{
          vote_id: vote_id,
          comment: comment(result),
          model: model,
          user_id: user_id
        }

        if correct_answer do
          # If the quote supports a different answer, correct the vote, then verify.
          if to_string(vote.answer) != correct_answer do
            Votes.update_vote(vote, %{answer: correct_answer})
          end

          create_vote_verification(Map.put(attrs, :status, :ai_verified), vote_id)
        else
          create_vote_verification(Map.put(attrs, :status, :ai_unverifiable), vote_id)
        end
    end
  end

  defp create_vote_verification(attrs, vote_id) do
    case VoteVerifications.create_verification(attrs) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to record vote verification for ##{vote_id}: #{inspect(reason)}")
        :ok
    end
  end

  # --- Cascade helpers --------------------------------------------------------

  defp enqueue_relevance(opinion_id) do
    from(os in OpinionStatement, where: os.opinion_id == ^opinion_id, select: os.id)
    |> Repo.all()
    |> Enum.each(&enqueue("relevance", &1))
  end

  defp enqueue_votes(%OpinionStatement{opinion_id: opinion_id, statement_id: statement_id}) do
    from(v in Vote,
      where: v.opinion_id == ^opinion_id and v.statement_id == ^statement_id,
      select: v.id
    )
    |> Repo.all()
    |> Enum.each(&enqueue("vote", &1))
  end

  defp enqueue(subject, id) do
    %{"subject" => subject, "id" => id}
    |> VerificationWorker.new()
    |> Oban.insert()
  end

  defp unlink(%OpinionStatement{opinion_id: opinion_id, statement_id: statement_id}) do
    opinion = Opinions.get_opinion(opinion_id)
    statement = Statements.get_statement(statement_id)

    if opinion && statement do
      Opinions.remove_opinion_from_statement(opinion, statement)
    end

    :ok
  end

  # --- Result parsing ---------------------------------------------------------

  defp normalize_status(status) when is_binary(status) do
    normalized = Map.get(@status_aliases, status, status)
    if normalized in @allowed_statuses, do: String.to_existing_atom(normalized), else: :ai_unverifiable
  end

  defp normalize_status(_), do: :ai_unverifiable

  defp normalize_answer(answer) when is_binary(answer) do
    downcased = String.downcase(answer)
    if downcased in @answers, do: downcased, else: nil
  end

  defp normalize_answer(_), do: nil

  defp comment(result), do: result["comment"] || "AI verification"

  # Never store "human" so resolve/1 treats it as an AI verification.
  defp model(result) do
    case result["model"] do
      model when is_binary(model) and model != "" and model != "human" -> model
      _ -> "ai"
    end
  end

  defp system_user_id do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
    end
  end
end
