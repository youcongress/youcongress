defmodule YouCongress.Track do
  @moduledoc """
  Track events with Amplitude
  """

  alias YouCongress.{Amplitude, Authors}

  def event(_, nil), do: nil

  def event(event_type, current_user) do
    %{event_type: event_type, current_user_id: current_user.id, author_id: current_user.author_id}
    |> YouCongress.Workers.TrackWorker.new()
    |> Oban.insert()
  end

  def track_now(event_type, current_user_id, author_id) do
    if Amplitude.enabled?() do
      author = Authors.get_author!(author_id)
      user_id = amplitude_user_id(author.twitter_username, current_user_id)

      Amplitude.deliver_event(event_type, user_id)
    else
      :ok
    end
  end

  defp amplitude_user_id(nil, current_user_id), do: "user_id:#{current_user_id}"

  defp amplitude_user_id(twitter_username, current_user_id) do
    "twitter:" <> twitter_username <> "; user_id:#{current_user_id}"
  end
end
