defmodule YouCongress.Workers.BackfillOpinionEmbeddingWorker do
  @moduledoc """
  Backfills the content embedding for a single sourced quote.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  import Ecto.Query

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo

  @doc """
  Enqueues a backfill job for each sourced quote missing an embedding.

  Pass an integer `limit` to cap the number of jobs enqueued. Returns the
  number of jobs successfully enqueued.
  """
  def enqueue_all(limit \\ nil) do
    limit = normalize_limit(limit)

    opinion_ids(limit)
    |> Enum.reduce(0, fn opinion_id, count ->
      case %{opinion_id: opinion_id} |> new() |> Oban.insert() do
        {:ok, _job} -> count + 1
        {:error, _reason} -> count
      end
    end)
  end

  defp opinion_ids(limit) do
    query =
      from(o in Opinion,
        where: not is_nil(o.source_url) and is_nil(o.content_embedding),
        order_by: [asc: o.id],
        select: o.id
      )

    query = if is_integer(limit), do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  defp normalize_limit(nil), do: nil
  defp normalize_limit(limit), do: max(limit, 0)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"opinion_id" => opinion_id}}) do
    case Repo.get(Opinion, opinion_id) do
      nil ->
        :ok

      %Opinion{source_url: nil} ->
        :ok

      %Opinion{content_embedding: embedding} when not is_nil(embedding) ->
        :ok

      %Opinion{} = opinion ->
        with {:ok, _opinion} <- Opinions.update_opinion(opinion, %{content: opinion.content}) do
          :ok
        end
    end
  end
end
