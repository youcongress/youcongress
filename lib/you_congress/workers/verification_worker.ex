defmodule YouCongress.Workers.VerificationWorker do
  @moduledoc """
  Starts an LLM verification job for one subject and enqueues a polling worker to
  collect the result.

  Args:
  - subject: "quote" (opinion_id), "relevance" (opinion_statement_id) or "vote" (vote_id)
  - id: the subject's id
  - opinion_id: optional quote id for vote jobs, used when verifying a vote from
    a specific quote page even if the vote currently points at another quote.
  - correction_attempts: optional quote correction loop count. Quote jobs stop
    asking the verifier for more corrections after the configured cutoff.
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
  alias YouCongress.Verifications.QuoteCorrectionLoop
  alias YouCongress.Verifications.Verifier
  alias YouCongress.Workers.JobMetadata
  alias YouCongress.Workers.VerificationPollingWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject" => subject, "id" => id} = args} = job) do
    case load(subject, id, args) do
      {:skip, reason} ->
        JobMetadata.put(job, "verification", %{
          "status" => "skipped",
          "subject" => subject,
          "subject_id" => id,
          "reason" => JobMetadata.format_reason(reason)
        })

        :ok

      {:ok, record} ->
        case Verifier.submit(subject_type(subject), record, verifier_opts(args)) do
          {:ok, job_id} ->
            JobMetadata.put(job, "verification", %{
              "status" => "submitted",
              "subject" => subject,
              "subject_id" => id,
              "verification_job_id" => job_id
            })

            polling_result =
              %{"subject" => subject, "id" => id, "job_id" => job_id}
              |> maybe_put_context(args, "opinion_id")
              |> maybe_put_context(args, "correction_attempts")
              |> maybe_put_verification_worker_job_id(job)
              |> VerificationPollingWorker.new()
              |> Oban.insert()

            case polling_result do
              {:ok, _polling_job} ->
                :ok

              {:error, reason} ->
                JobMetadata.put(job, "verification", %{
                  "status" => "failed",
                  "stage" => "enqueue_polling",
                  "subject" => subject,
                  "subject_id" => id,
                  "verification_job_id" => job_id,
                  "reason" => JobMetadata.format_reason(reason)
                })

                {:error, reason}
            end

          {:error, reason} ->
            JobMetadata.put(job, "verification", %{
              "status" => "failed",
              "stage" => "submit",
              "subject" => subject,
              "subject_id" => id,
              "reason" => JobMetadata.format_reason(reason)
            })

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

  defp load("quote", id, _args) do
    case Opinions.get_opinion(id) do
      nil -> {:skip, :quote_not_found}
      %Opinion{source_url: nil} -> {:skip, :quote_has_no_source_url}
      %Opinion{} = opinion -> {:ok, opinion}
    end
  end

  defp load("relevance", id, _args) do
    case Repo.get(OpinionStatement, id) do
      nil -> {:skip, :relevance_not_found}
      %OpinionStatement{} = opinion_statement -> {:ok, opinion_statement}
    end
  end

  defp load("vote", id, %{"opinion_id" => opinion_id}) when not is_nil(opinion_id) do
    load_vote_with_opinion(id, opinion_id)
  end

  defp load("vote", id, _args) do
    case Votes.get_vote(id) do
      nil -> {:skip, :vote_not_found}
      %Vote{} = vote -> {:ok, vote}
    end
  end

  defp load(_subject, _id, _args), do: {:skip, :unsupported_subject}

  defp load_vote_with_opinion(vote_id, opinion_id) do
    case {Votes.get_vote(vote_id), Opinions.get_opinion(normalize_id(opinion_id))} do
      {nil, _opinion} ->
        {:skip, :vote_not_found}

      {%Vote{}, nil} ->
        {:skip, :opinion_not_found}

      {%Vote{} = vote, %Opinion{} = opinion} ->
        if valid_vote_opinion?(vote, opinion) do
          {:ok, %{vote | opinion_id: opinion.id, opinion: opinion}}
        else
          {:skip, :vote_opinion_context_invalid}
        end
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

  defp maybe_put_verification_worker_job_id(args, %Oban.Job{id: id}) when is_integer(id) do
    Map.put(args, "verification_worker_job_id", id)
  end

  defp maybe_put_verification_worker_job_id(args, _job), do: args

  defp verifier_opts(%{"subject" => "quote"} = args) do
    [
      correction_attempts: QuoteCorrectionLoop.correction_attempts(args),
      allow_quote_correction?: QuoteCorrectionLoop.allow_correction?(args)
    ]
  end

  defp verifier_opts(_args), do: []

  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)
end
