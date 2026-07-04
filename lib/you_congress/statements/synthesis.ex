defmodule YouCongress.Statements.Synthesis do
  @moduledoc """
  Coordinates AI-generated syntheses of the sourced quotes on a statement.

  A synthesis is a structured overview (headline, clustered arguments for and
  against, insights, conclusion) generated in a background OpenAI job for
  statements with at least `min_quotes/0` quotes. The LLM only cites quotes by
  opinion_id; the UI renders the actual quote content and authors from the
  database, and the vote tally always comes from the votes table.
  """

  import Ecto.Query

  require Logger

  alias YouCongress.FeatureFlags
  alias YouCongress.Opinions
  alias YouCongress.Repo
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Workers.StatementSynthesisWorker

  @min_quotes 25
  @staleness_delta 10
  @max_clusters_per_side 5
  @max_opinion_ids_per_cluster 6
  @max_insights 5
  @cluster_keys ["arguments_for", "arguments_against", "middle_ground"]

  @submit_worker "YouCongress.Workers.StatementSynthesisWorker"
  @polling_worker "YouCongress.Workers.StatementSynthesisPollingWorker"

  @callback submit(Statement.t(), [Vote.t()]) :: {:ok, binary()} | {:error, term()}
  @callback check_job_status(binary()) ::
              {:ok, :completed, map()} | {:ok, :in_progress} | {:error, term()}

  def min_quotes, do: @min_quotes

  def cluster_keys, do: @cluster_keys

  def submit(%Statement{} = statement, votes), do: implementation().submit(statement, votes)

  def check_job_status(job_id) when is_binary(job_id),
    do: implementation().check_job_status(job_id)

  @doc "Number of quotes shown on the statement page (votes with a sourced opinion)."
  def quotes_count(statement_id) do
    Votes.count_with_opinion_source(statement_id, source_filter: :quotes)
  end

  @doc """
  Whether a synthesis should be (re)generated: the feature is on, the statement
  has enough quotes, and there is either no synthesis yet or the quote count
  has grown by at least the staleness delta since it was generated.
  """
  def eligible?(%Statement{} = statement, quotes_count) do
    FeatureFlags.enabled?(:quote_synthesis) and quotes_count >= @min_quotes and
      (is_nil(statement.synthesis) or
         quotes_count - (statement.synthesis_quotes_count || 0) >= @staleness_delta)
  end

  @doc """
  Enqueues a synthesis job when the statement is eligible. Never errors: it
  runs inside the opinions-count sync worker and must not fail it.
  """
  def maybe_enqueue(%Statement{} = statement) do
    if eligible?(statement, quotes_count(statement.id)) do
      case %{"statement_id" => statement.id} |> StatementSynthesisWorker.new() |> Oban.insert() do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Logger.error(
            "Failed to enqueue synthesis for statement #{statement.id}: #{inspect(reason)}"
          )

          :ok
      end
    else
      :ok
    end
  end

  @doc """
  Enqueues a regeneration (admin action), bypassing the staleness delta but not
  the feature flag or the quote floor (both re-checked in the worker). Returns
  `{:ok, job}` with `job.conflict?` set when a synthesis run is already active.
  """
  def enqueue_regeneration(statement_id) when is_integer(statement_id) do
    case active_synthesis_job(statement_id) do
      nil ->
        %{"statement_id" => statement_id, "force" => true}
        |> StatementSynthesisWorker.new()
        |> Oban.insert()

      %Oban.Job{} = job ->
        {:ok, %{job | conflict?: true}}
    end
  end

  @doc "Whether a synthesis submit or polling job is active for the statement."
  def in_progress?(statement_id) when is_integer(statement_id) do
    not is_nil(active_synthesis_job(statement_id))
  end

  @doc """
  Whether a polling job is active for the statement. The submit worker checks
  this before submitting: Oban uniqueness is per-worker, so the submit job's
  uniqueness alone cannot see an OpenAI job that is already being polled.
  """
  def polling_in_progress?(statement_id) when is_integer(statement_id) do
    not is_nil(active_synthesis_job(statement_id, [@polling_worker]))
  end

  defp active_synthesis_job(statement_id, worker_names \\ [@submit_worker, @polling_worker]) do
    from(j in Oban.Job,
      where: j.worker in ^worker_names,
      where: fragment("?->>'statement_id' = ?", j.args, ^to_string(statement_id)),
      where: j.state in ["scheduled", "available", "executing", "retryable"],
      order_by: [desc: j.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc "All opinion ids cited across the synthesis clusters."
  def cited_opinion_ids(synthesis) when is_map(synthesis) do
    @cluster_keys
    |> Enum.flat_map(fn key -> List.wrap(synthesis[key]) end)
    |> Enum.flat_map(fn
      %{"opinion_ids" => ids} when is_list(ids) -> ids
      _ -> []
    end)
    |> Enum.uniq()
  end

  def cited_opinion_ids(_), do: []

  @doc "Ids of the quotes currently attached to the statement."
  def valid_quote_ids(statement_id) do
    Opinions.list_opinions(statement_ids: [statement_id], only_quotes: true)
    |> MapSet.new(& &1.id)
  end

  @doc """
  Validates and normalizes a raw synthesis payload from the LLM.

  Requires nonblank `headline` and `conclusion` strings (an undecodable model
  response reaches us as a map without them). Keeps only clusters with string
  title/summary and at least one cited opinion_id that is a current quote of
  the statement; caps clusters, ids and insights.
  """
  def sanitize(raw, %MapSet{} = valid_ids) when is_map(raw) do
    with {:ok, headline} <- fetch_nonblank(raw, "headline"),
         {:ok, conclusion} <- fetch_nonblank(raw, "conclusion") do
      clean =
        %{
          "headline" => headline,
          "conclusion" => conclusion,
          "insights" => sanitize_insights(raw["insights"])
        }
        |> Map.merge(sanitize_clusters(raw, valid_ids))
        |> maybe_put_model(raw)

      {:ok, clean}
    end
  end

  def sanitize(_raw, _valid_ids), do: {:error, :invalid_synthesis}

  @doc """
  Enqueues syntheses for all statements with at least `min_quotes/0` quotes.

  Options:

    * `:force` - also regenerate statements that already have a synthesis
    * `:limit` - maximum number of statements to enqueue
    * `:dry_run` - only return the candidates, without enqueuing
    * `:stagger_in_seconds` - delay between submissions (default 60), so a
      backfill does not slam the queue or OpenAI

  Returns the list of `{statement, quotes_count}` candidates.
  """
  def backfill(opts \\ []) do
    stagger = Keyword.get(opts, :stagger_in_seconds, 60)

    candidates =
      Statements.list_statements()
      |> Enum.map(&{&1, quotes_count(&1.id)})
      |> Enum.filter(fn {statement, count} ->
        count >= @min_quotes and (opts[:force] || is_nil(statement.synthesis))
      end)
      |> maybe_take(opts[:limit])

    unless opts[:dry_run] do
      candidates
      |> Enum.with_index()
      |> Enum.each(fn {{statement, _count}, index} ->
        %{"statement_id" => statement.id, "force" => true}
        |> StatementSynthesisWorker.new(schedule_in: index * stagger)
        |> Oban.insert()
      end)
    end

    candidates
  end

  defp sanitize_clusters(raw, valid_ids) do
    Map.new(@cluster_keys, fn key ->
      clusters =
        raw[key]
        |> List.wrap()
        |> Enum.filter(&valid_cluster_shape?/1)
        |> Enum.map(fn cluster ->
          ids =
            (cluster["opinion_ids"] || [])
            |> Enum.filter(&is_integer/1)
            |> Enum.uniq()
            |> Enum.filter(&MapSet.member?(valid_ids, &1))
            |> Enum.take(@max_opinion_ids_per_cluster)

          %{"title" => cluster["title"], "summary" => cluster["summary"], "opinion_ids" => ids}
        end)
        |> Enum.reject(&(&1["opinion_ids"] == []))
        |> Enum.take(@max_clusters_per_side)

      {key, clusters}
    end)
  end

  defp valid_cluster_shape?(%{"title" => title, "summary" => summary})
       when is_binary(title) and is_binary(summary) do
    String.trim(title) != "" and String.trim(summary) != ""
  end

  defp valid_cluster_shape?(_), do: false

  defp sanitize_insights(insights) when is_list(insights) do
    insights
    |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
    |> Enum.take(@max_insights)
  end

  defp sanitize_insights(_), do: []

  defp fetch_nonblank(map, key) do
    case map[key] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :invalid_synthesis}, else: {:ok, value}

      _ ->
        {:error, :invalid_synthesis}
    end
  end

  defp maybe_put_model(clean, %{"model" => model}) when is_binary(model),
    do: Map.put(clean, "model", model)

  defp maybe_put_model(clean, _), do: clean

  defp maybe_take(list, nil), do: list
  defp maybe_take(list, limit), do: Enum.take(list, limit)

  defp implementation do
    Application.get_env(
      :you_congress,
      :quote_synthesis_implementation,
      YouCongress.Statements.SynthesisAI
    )
  end
end
