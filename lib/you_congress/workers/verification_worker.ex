defmodule YouCongress.Workers.VerificationWorker do
  @moduledoc """
  Starts an LLM verification job for one subject and enqueues a polling worker to
  collect the result.

  Args:
  - subject: "quote" (opinion_id), "relevance" (opinion_statement_id) or "vote" (vote_id)
  - id: the subject's id
  - opinion_id: optional quote id for vote jobs, used when verifying a vote from
    a specific quote page even if the vote currently points at another quote.
  """

  use Oban.Worker,
    queue: :verification,
    max_attempts: 1,
    unique: [states: [:scheduled, :available], keys: [:subject, :id, :opinion_id]]

  require Logger

  alias YouCongress.Repo
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Verifications.Verifier
  alias YouCongress.Workers.VerificationPollingWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject" => subject, "id" => id} = args}) do
    case load(subject, id, args) do
      nil ->
        :ok

      record ->
        case Verifier.submit(subject_type(subject), record) do
          {:ok, job_id} ->
            %{"subject" => subject, "id" => id, "job_id" => job_id}
            |> maybe_put_context(args, "opinion_id")
            |> VerificationPollingWorker.new()
            |> Oban.insert()

            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to submit #{subject} verification for ##{id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  defp subject_type("quote"), do: :quote
  defp subject_type("relevance"), do: :relevance
  defp subject_type("vote"), do: :vote

  defp load("quote", id, _args), do: load_quote(Opinions.get_opinion(id))
  defp load("relevance", id, _args), do: Repo.get(OpinionStatement, id)

  defp load("vote", id, %{"opinion_id" => opinion_id}) when not is_nil(opinion_id) do
    load_vote_with_opinion(id, opinion_id)
  end

  defp load("vote", id, _args), do: Votes.get_vote(id)
  defp load(_subject, _id, _args), do: nil

  # Quietly skip plain opinions: only sourced quotes are verified.
  defp load_quote(%Opinion{source_url: nil}), do: nil
  defp load_quote(opinion), do: opinion

  defp load_vote_with_opinion(vote_id, opinion_id) do
    with %Vote{} = vote <- Votes.get_vote(vote_id),
         opinion_id <- normalize_id(opinion_id),
         %Opinion{} = opinion <- Opinions.get_opinion(opinion_id),
         true <- valid_vote_opinion?(vote, opinion) do
      %{vote | opinion_id: opinion.id, opinion: opinion}
    else
      _ -> nil
    end
  end

  defp valid_vote_opinion?(%Vote{} = vote, %Opinion{} = opinion) do
    opinion.author_id == vote.author_id and
      not is_nil(opinion.source_url) and
      not is_nil(OpinionsStatements.get_opinion_statement(opinion.id, vote.statement_id))
  end

  defp maybe_put_context(target, source, key) do
    case Map.fetch(source, key) do
      {:ok, value} when not is_nil(value) -> Map.put(target, key, value)
      _ -> target
    end
  end

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
end
