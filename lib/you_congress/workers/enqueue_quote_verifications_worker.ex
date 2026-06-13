defmodule YouCongress.Workers.EnqueueQuoteVerificationsWorker do
  @moduledoc """
  Enqueues an AI verification job for every sourced quote.

  Each quote's verification cascades to its statement-relevance links and, in
  turn, to the votes that cite it, so this single batch re-verifies the whole
  pipeline. Jobs are staggered to avoid bursts of LLM calls.

  Optional args:
  - limit: maximum number of quotes to enqueue. Omit to enqueue all quotes.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Opinions
  alias YouCongress.Workers.VerificationWorker

  @stagger_interval 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> list_opinion_opts()
    |> Opinions.list_opinions()
    |> Enum.with_index()
    |> Enum.each(fn {opinion, index} ->
      %{"subject" => "quote", "id" => opinion.id}
      |> VerificationWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end

  defp list_opinion_opts(args) when is_map(args) do
    opts = [only_quotes: true, order_by: [asc: :id]]

    case Map.get(args, "limit") || Map.get(args, :limit) do
      limit when is_integer(limit) and limit >= 0 -> Keyword.put(opts, :limit, limit)
      _ -> opts
    end
  end

  defp list_opinion_opts(_args), do: [only_quotes: true, order_by: [asc: :id]]
end
