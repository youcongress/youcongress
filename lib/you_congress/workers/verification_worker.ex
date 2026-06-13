defmodule YouCongress.Workers.VerificationWorker do
  @moduledoc """
  Starts an LLM verification job for one subject and enqueues a polling worker to
  collect the result.

  Args:
  - subject: "quote" (opinion_id), "relevance" (opinion_statement_id) or "vote" (vote_id)
  - id: the subject's id
  """

  use Oban.Worker,
    queue: :verification,
    max_attempts: 1,
    unique: [states: [:scheduled, :available], keys: [:subject, :id]]

  require Logger

  alias YouCongress.Repo
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes
  alias YouCongress.Verifications.Verifier
  alias YouCongress.Workers.VerificationPollingWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"subject" => subject, "id" => id}}) do
    case load(subject, id) do
      nil ->
        :ok

      record ->
        case Verifier.submit(subject_type(subject), record) do
          {:ok, job_id} ->
            %{"subject" => subject, "id" => id, "job_id" => job_id}
            |> VerificationPollingWorker.new()
            |> Oban.insert()

            :ok

          {:error, reason} ->
            Logger.error("Failed to submit #{subject} verification for ##{id}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp subject_type("quote"), do: :quote
  defp subject_type("relevance"), do: :relevance
  defp subject_type("vote"), do: :vote

  defp load("quote", id), do: load_quote(Opinions.get_opinion(id))
  defp load("relevance", id), do: Repo.get(OpinionStatement, id)
  defp load("vote", id), do: Votes.get_vote(id)
  defp load(_subject, _id), do: nil

  # Quietly skip plain opinions: only sourced quotes are verified.
  defp load_quote(%Opinion{source_url: nil}), do: nil
  defp load_quote(opinion), do: opinion
end
