defmodule YouCongress.Workers.BackfillOpinionEmbeddingWorker do
  @moduledoc """
  Backfills the content embedding for a single sourced quote.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo

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
