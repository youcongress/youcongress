defmodule YouCongress.Workers.TrackWorker do
  @moduledoc """
  Track events with Amplitude
  """

  use Oban.Worker

  def perform(%Oban.Job{
        args: %{
          "event_type" => event_type,
          "current_user_id" => current_user_id,
          "author_id" => author_id
        }
      }) do
    YouCongress.Track.track_now(event_type, current_user_id, author_id)
  end
end
