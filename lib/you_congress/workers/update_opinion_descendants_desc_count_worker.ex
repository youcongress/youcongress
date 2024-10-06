defmodule YouCongress.Workers.UpdateOpinionDescendantsCountWorker do
  @moduledoc """
  Updates the descendants count of an opinion.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Opinions

  @impl true
  def perform(%Oban.Job{args: %{"opinion_id" => opinion_id}}) do
    case Opinions.get_opinion(opinion_id) do
      nil -> :ok
      opinion -> Opinions.update_descendants_count(opinion)
    end
  end
end
