defmodule YouCongress.Workers.MatchQuoteStatementsWorker do
  @moduledoc """
  Starts a background AI job to discover statements related to a sourced quote
  and enqueues a polling worker to collect the result.

  Args:
  - opinion_id: the sourced quote id.
  """

  use Oban.Worker,
    queue: :verification,
    max_attempts: 1,
    unique: [states: [:scheduled, :available], keys: [:opinion_id]]

  require Logger

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements
  alias YouCongress.Statements
  alias YouCongress.Verifications.QuoteStatementMatcher
  alias YouCongress.Workers.JobMetadata
  alias YouCongress.Workers.MatchQuoteStatementsPollingWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opinion_id" => opinion_id}} = job) do
    case load_submission(opinion_id) do
      {:skip, reason} ->
        store_metadata(job, %{
          "status" => "skipped",
          "opinion_id" => opinion_id,
          "reason" => JobMetadata.format_reason(reason)
        })

        Logger.info("Skipping statement matching for quote #{inspect(opinion_id)}: #{reason}")
        :ok

      {:ok, opinion, statements} ->
        submit(job, opinion, statements)
    end
  end

  defp submit(job, opinion, statements) do
    opinion_id = opinion.id

    case QuoteStatementMatcher.submit(opinion, statements) do
      {:ok, llm_job_id} ->
        store_metadata(job, %{
          "status" => "submitted",
          "opinion_id" => opinion_id,
          "matching_job_id" => llm_job_id,
          "candidate_count" => length(statements)
        })

        polling_result =
          %{
            "opinion_id" => opinion_id,
            "job_id" => llm_job_id,
            "statement_ids" => Enum.map(statements, & &1.id)
          }
          |> maybe_put_matching_worker_job_id(job)
          |> MatchQuoteStatementsPollingWorker.new()
          |> Oban.insert()

        case polling_result do
          {:ok, _polling_job} ->
            :ok

          {:error, reason} ->
            store_metadata(job, %{
              "status" => "failed",
              "stage" => "enqueue_polling",
              "opinion_id" => opinion_id,
              "matching_job_id" => llm_job_id,
              "reason" => JobMetadata.format_reason(reason)
            })

            {:error, reason}
        end

      {:error, reason} ->
        store_metadata(job, %{
          "status" => "failed",
          "stage" => "submit",
          "opinion_id" => opinion_id,
          "reason" => JobMetadata.format_reason(reason)
        })

        Logger.error(
          "Failed to submit statement matching for quote ##{inspect(opinion_id)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp load_submission(opinion_id) do
    with user_id when not is_nil(user_id) <- system_user_id(),
         %Opinion{} = opinion <- load_quote(opinion_id) do
      case candidate_statements(opinion) do
        [] ->
          {:skip, :no_candidate_statements}

        statements ->
          {:ok, opinion, statements}
      end
    else
      nil ->
        if is_nil(system_user_id()),
          do: {:skip, :verification_user_not_configured},
          else: {:skip, :quote_not_found_or_ineligible}
    end
  end

  defp load_quote(opinion_id) do
    case Opinions.get_opinion(normalize_id(opinion_id)) do
      %Opinion{source_url: nil} -> nil
      %Opinion{author_id: nil} -> nil
      %Opinion{} = opinion -> opinion
      nil -> nil
    end
  end

  defp candidate_statements(%Opinion{id: opinion_id}) do
    statements = Statements.list_statements(order: :id_asc)
    statement_ids = Enum.map(statements, & &1.id)

    linked_statement_ids =
      opinion_id
      |> OpinionsStatements.get_opinion_statements_by_statement_ids(statement_ids)
      |> Map.keys()
      |> MapSet.new()

    Enum.reject(statements, &MapSet.member?(linked_statement_ids, &1.id))
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  defp system_user_id do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> id
      id when is_binary(id) -> normalize_id(id)
    end
  end

  defp maybe_put_matching_worker_job_id(args, %Oban.Job{id: id}) when is_integer(id) do
    Map.put(args, "matching_worker_job_id", id)
  end

  defp maybe_put_matching_worker_job_id(args, _job), do: args

  defp store_metadata(job, metadata) do
    JobMetadata.put(job, "quote_statement_matching", metadata)
  end
end
