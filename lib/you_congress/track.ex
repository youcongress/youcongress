defmodule YouCongress.Track do
  @moduledoc """
  Track events with Amplitude
  """

  alias YouCongress.{Amplitude, AnalyticsConsent}

  def event(_, nil), do: nil

  def event(event_type, current_user) do
    if AnalyticsConsent.granted?() do
      %{
        event_type: event_type,
        current_user_id: current_user.id,
        author_id: current_user.author_id,
        analytics_consent: true
      }
      |> YouCongress.Workers.TrackWorker.new()
      |> Oban.insert()
    else
      :ok
    end
  end

  def track_now(event_type, current_user_id, author_id, analytics_consent \\ false) do
    if analytics_consent and Amplitude.enabled?() do
      user_id = amplitude_user_id(current_user_id, author_id)

      Amplitude.deliver_event(event_type, user_id, %{}, analytics_consent: true)
    else
      :ok
    end
  end

  def format_user_identifier(user_id), do: "user_id:#{user_id}"

  def amplitude_user_id(current_user_id, _author_id), do: format_user_identifier(current_user_id)
end
