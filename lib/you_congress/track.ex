defmodule YouCongress.Track do
  @moduledoc """
  Track events with Amplitude
  """

  @api_url "https://api.eu.amplitude.com/2/httpapi"

  alias YouCongress.Authors

  def event(_, nil), do: nil

  def event(event_type, current_user) do
    api_key = Application.get_env(:you_congress, :amplitude_api_key)

    if api_key do
      spawn(fn ->
        author = Authors.get_author!(current_user.author_id)

        body = %{
          "api_key" => api_key,
          "events" => [
            %{
              "event_type" => event_type,
              "user_id" => amplitude_user_id(author.twitter_username, current_user)
            }
          ]
        }

        headers = [{"Content-Type", "application/json"}, {"Accept", "*/*"}]

        Finch.build(:post, @api_url, headers, Jason.encode!(body))
        |> Finch.request(YouCongress.Finch)
      end)
    end
  end

  defp amplitude_user_id(nil, current_user), do: "user_id:" <> current_user.id

  defp amplitude_user_id(twitter_username, current_user) do
    "twitter:" <> twitter_username <> "; user_id:#{current_user.id}"
  end
end
