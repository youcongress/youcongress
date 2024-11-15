defmodule YouCongress.Workers.UpdateOpinionLikesCountWorker do
  @moduledoc """
  Updates the likes count of an opinion.
  """

  require Logger

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Opinions
  alias YouCongress.Workers.Votings.SyncVotingLikesCountWorker

  @impl true
  def perform(%Oban.Job{args: %{"opinion_id" => opinion_id}}) do
    opinion = Opinions.get_opinion!(opinion_id)

    case Opinions.update_opinion_likes_count(opinion) do
      {:ok, opinion} ->
        %{voting_id: opinion.voting_id}
        |> SyncVotingLikesCountWorker.new()
        |> Oban.insert()

      _ ->
        Logger.error("Failed to update opinion likes count for opinion #{opinion.id}")
        :ok
    end
  end
end
