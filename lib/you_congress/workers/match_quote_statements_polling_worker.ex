defmodule YouCongress.Workers.MatchQuoteStatementsPollingWorker do
  @moduledoc """
  Polls for a quote-to-statement matching result and persists completed matches.

  Retries every minute for up to 90 minutes, mirroring
  `YouCongress.Workers.VerificationPollingWorker`.
  """

  use Oban.Worker, queue: :verification, max_attempts: 90

  require Logger

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements
  alias YouCongress.Verifications.QuoteStatementMatcher
  alias YouCongress.Votes
  alias YouCongress.Workers.JobMetadata

  @answers ~w(for against abstain)

  @impl Oban.Worker
  def perform(
        %Oban.Job{
          args:
            %{
              "opinion_id" => opinion_id,
              "job_id" => llm_job_id,
              "statement_ids" => statement_ids
            } = args
        } = job
      ) do
    case QuoteStatementMatcher.check_job_status(llm_job_id) do
      {:ok, :completed, matches} ->
        matched_count = persist_matches(opinion_id, statement_ids, matches)

        store_metadata(job, args, %{
          "status" => "completed",
          "opinion_id" => opinion_id,
          "matching_job_id" => llm_job_id,
          "matched_count" => matched_count
        })

        :ok

      {:ok, :in_progress} ->
        store_metadata(job, args, %{
          "status" => "in_progress",
          "opinion_id" => opinion_id,
          "matching_job_id" => llm_job_id
        })

        {:snooze, 60}

      {:error, reason} ->
        store_metadata(job, args, %{
          "status" => "cancelled",
          "opinion_id" => opinion_id,
          "matching_job_id" => llm_job_id,
          "reason" => JobMetadata.format_reason(reason)
        })

        Logger.error(
          "Statement matching job #{llm_job_id} (quote ##{opinion_id}) failed: #{inspect(reason)}"
        )

        {:cancel, reason}
    end
  end

  defp persist_matches(opinion_id, statement_ids, matches) when is_list(matches) do
    with user_id when not is_nil(user_id) <- system_user_id(),
         %Opinion{} = opinion <- load_quote(opinion_id) do
      statements_by_id = candidate_statements_by_id(statement_ids)

      matches
      |> Enum.map(&normalize_match/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(fn {statement_id, _answer} -> statement_id end)
      |> Enum.count(fn {statement_id, answer} ->
        case Map.fetch(statements_by_id, statement_id) do
          {:ok, statement} -> persist_match(opinion, statement, answer, user_id)
          :error -> false
        end
      end)
    else
      nil -> 0
    end
  end

  defp persist_matches(_opinion_id, _statement_ids, _matches), do: 0

  defp load_quote(opinion_id) do
    case Opinions.get_opinion(normalize_id(opinion_id)) do
      %Opinion{source_url: nil} -> nil
      %Opinion{author_id: nil} -> nil
      %Opinion{} = opinion -> opinion
      nil -> nil
    end
  end

  defp candidate_statements_by_id(statement_ids) do
    statement_ids = statement_ids |> Enum.map(&normalize_id/1) |> MapSet.new()

    Statements.list_statements(order: :id_asc)
    |> Enum.filter(&MapSet.member?(statement_ids, &1.id))
    |> Map.new(&{&1.id, &1})
  end

  defp persist_match(%Opinion{} = opinion, statement, answer, user_id) do
    with :ok <- link_opinion_statement(opinion, statement, user_id),
         {:ok, _vote} <- create_or_update_vote(opinion, statement, answer) do
      true
    else
      {:error, reason} ->
        Logger.error(
          "Failed to persist statement match for quote #{opinion.id} and statement #{statement.id}: #{inspect(reason)}"
        )

        false
    end
  end

  defp link_opinion_statement(%Opinion{} = opinion, statement, user_id) do
    case Opinions.add_opinion_to_statement(opinion, statement, user_id) do
      {:ok, _opinion} -> :ok
      {:error, :already_associated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_or_update_vote(%Opinion{author_id: author_id} = opinion, statement, answer) do
    attrs = %{
      statement_id: statement.id,
      author_id: author_id,
      answer: answer,
      opinion_id: opinion.id,
      direct: true,
      twin: false
    }

    case Votes.get_by(statement_id: statement.id, author_id: author_id) do
      nil -> Votes.create_vote(attrs)
      vote -> Votes.update_vote(vote, attrs)
    end
  end

  defp normalize_match(match) when is_map(match) do
    statement_id = normalize_id(match["statement_id"] || match[:statement_id])
    answer = normalize_answer(match["answer"] || match[:answer])

    if statement_id && answer, do: {statement_id, answer}, else: nil
  end

  defp normalize_match(_), do: nil

  defp normalize_answer(answer) when is_binary(answer) do
    downcased = String.downcase(answer)
    if downcased in @answers, do: String.to_existing_atom(downcased), else: nil
  end

  defp normalize_answer(answer) when answer in [:for, :against, :abstain], do: answer
  defp normalize_answer(_), do: nil

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

  defp store_metadata(job, args, metadata) do
    metadata =
      if is_integer(job.id), do: Map.put(metadata, "polling_job_id", job.id), else: metadata

    JobMetadata.put(job, "quote_statement_matching", metadata)

    case args["matching_worker_job_id"] do
      job_id when is_integer(job_id) ->
        JobMetadata.put(job_id, "quote_statement_matching", metadata)

      _job_id ->
        :ok
    end
  end
end
