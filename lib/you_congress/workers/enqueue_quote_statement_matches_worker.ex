defmodule YouCongress.Workers.EnqueueQuoteStatementMatchesWorker do
  @moduledoc """
  Enqueues quote-statement discovery for sourced quotes.

  Optional args:
  - limit: maximum number of sourced quotes to enqueue. Omit to enqueue all.
  """

  use Oban.Worker, queue: :verification, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Workers.MatchQuoteStatementsWorker

  @stagger_interval 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> opinion_ids()
    |> Enum.with_index()
    |> Enum.each(fn {opinion_id, index} ->
      %{"opinion_id" => opinion_id}
      |> MatchQuoteStatementsWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end

  defp opinion_ids(args) do
    query =
      from(o in Opinion,
        where: not (is_nil(o.source_url) and is_nil(o.source_text)),
        order_by: [asc: o.id],
        select: o.id
      )

    args
    |> limit()
    |> maybe_limit(query)
    |> Repo.all()
  end

  defp limit(args) when is_map(args) do
    case Map.get(args, "limit") || Map.get(args, :limit) do
      limit when is_integer(limit) and limit >= 0 -> limit
      _ -> nil
    end
  end

  defp limit(_args), do: nil

  defp maybe_limit(nil, query), do: query
  defp maybe_limit(limit, query), do: Ecto.Query.limit(query, ^limit)
end
