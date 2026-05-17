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
      user_id = amplitude_user_id(current_user_id, author_id)

      Amplitude.deliver_event(event_type, user_id)
    else
      :ok
    end
  end

  def format_user_identifier(nil, user_id), do: "user_id:#{user_id}"

  def format_user_identifier(twitter_username, user_id) do
    "twitter:" <> twitter_username <> "; user_id:#{user_id}"
  end

  def amplitude_user_id(current_user_id, nil), do: format_user_identifier(nil, current_user_id)

  def amplitude_user_id(current_user_id, author_id) when is_integer(author_id) do
    author_id
    |> Authors.get_author!()
    |> Map.get(:twitter_username)
    |> format_user_identifier(current_user_id)
  end
end
