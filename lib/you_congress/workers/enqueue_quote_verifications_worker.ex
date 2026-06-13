defmodule YouCongress.Workers.EnqueueQuoteVerificationsWorker do
  @moduledoc """
  Enqueues an AI verification job for every sourced quote.

  Each quote's verification cascades to its statement-relevance links and, in
  turn, to the votes that cite it, so this single batch re-verifies the whole
  pipeline. Jobs are staggered to avoid bursts of LLM calls.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Opinions
  alias YouCongress.Workers.VerificationWorker

  @stagger_interval 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    [only_quotes: true, order_by: [asc: :id]]
    |> Opinions.list_opinions()
    |> Enum.with_index()
    |> Enum.each(fn {opinion, index} ->
      %{"subject" => "quote", "id" => opinion.id}
      |> VerificationWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
