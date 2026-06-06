defmodule YouCongress.Workers.EnqueueAuthorCountryInferenceWorker do
  @moduledoc """
  Finds all authors without a country and enqueues a country inference job for each one.

  Jobs are staggered to avoid bursts of LLM calls.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Authors
  alias YouCongress.Workers.SetAuthorCountryFromLLMWorker

  @stagger_interval 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    [country_id: nil, order_by: [asc: :id]]
    |> Authors.list_authors()
    |> Enum.with_index()
    |> Enum.each(fn {author, index} ->
      %{author_id: author.id}
      |> SetAuthorCountryFromLLMWorker.new(schedule_in: index * @stagger_interval)
      |> Oban.insert()
    end)

    :ok
  end
end
