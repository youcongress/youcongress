defmodule YouCongress.Track do
  @moduledoc """
  Track events with Amplitude
  """

  @api_url "https://api.eu.amplitude.com/2/httpapi"

  alias YouCongress.Authors

  def event(_, nil), do: nil

  def event(event_type, current_user) do
    %{event_type: event_type, current_user_id: current_user.id, author_id: current_user.author_id}
    |> YouCongress.Workers.TrackWorker.new()
    |> Oban.insert()
  end

  def track_now(event_type, current_user_id, author_id) do
    api_key = Application.get_env(:you_congress, :amplitude_api_key)

    if api_key do
      author = Authors.get_author!(author_id)

      body = %{
        "api_key" => api_key,
        "events" => [
          %{
            "event_type" => event_type,
            "user_id" => amplitude_user_id(author.twitter_username, current_user_id)
          }
        ]
      }

      headers = [{"Content-Type", "application/json"}, {"Accept", "*/*"}]

      :post
      |> Finch.build(@api_url, headers, Jason.encode!(body))
      |> Finch.request(YouCongress.Finch)
    end
  end

  defp amplitude_user_id(nil, current_user_id), do: "user_id:#{current_user_id}"

  defp amplitude_user_id(twitter_username, current_user_id) do
    "twitter:" <> twitter_username <> "; user_id:#{current_user_id}"
  end
end
