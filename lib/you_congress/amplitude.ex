defmodule YouCongress.Amplitude do
  @moduledoc """
  Helper module to send events to Amplitude either synchronously or via Oban.
  """

  @api_url "https://api.eu.amplitude.com/2/httpapi"

  alias YouCongress.Workers.AmplitudeEventWorker

  @doc """
  Returns true when an Amplitude API key is configured.
  """
  def enabled? do
    case Application.get_env(:you_congress, :amplitude_api_key) do
      key when is_binary(key) -> String.trim(key) != ""
      _ -> false
    end
  end

  @doc """
  Queue an event to be sent to Amplitude asynchronously.
  """
  def track_event(event_type, user_id, event_properties \\ %{}) do
    if enabled?() do
      args = %{
        "event_type" => event_type,
        "user_id" => normalize_user_id(user_id),
        "event_properties" => normalize_properties(event_properties)
      }

      args
      |> AmplitudeEventWorker.new()
      |> Oban.insert()
    else
      :ok
    end
  end

  @doc """
  Send an event to Amplitude immediately.
  """
  def deliver_event(event_type, user_id, event_properties \\ %{}) do
    case Application.get_env(:you_congress, :amplitude_api_key) do
      key when is_binary(key) and key != "" ->
        payload =
          %{
            "api_key" => key,
            "events" => [build_event(event_type, user_id, event_properties)]
          }

        headers = [{"Content-Type", "application/json"}, {"Accept", "*/*"}]

        :post
        |> Finch.build(@api_url, headers, Jason.encode!(payload))
        |> Finch.request(Swoosh.Finch)

      _ ->
        :ok
    end
  end

  defp build_event(event_type, user_id, event_properties) do
    %{
      "event_type" => event_type,
      "user_id" => normalize_user_id(user_id),
      "event_properties" => normalize_properties(event_properties)
    }
  end

  defp normalize_user_id(nil), do: nil
  defp normalize_user_id(user_id) when is_binary(user_id), do: user_id
  defp normalize_user_id(user_id), do: to_string(user_id)

  defp normalize_properties(nil), do: %{}
  defp normalize_properties(properties) when properties == %{}, do: %{}

  defp normalize_properties(properties) when is_map(properties) do
    properties
    |> Enum.map(fn {key, value} -> {normalize_property_key(key), value} end)
    |> Map.new()
  end

  defp normalize_properties(properties) do
    properties
    |> Enum.map(fn {key, value} -> {normalize_property_key(key), value} end)
    |> Map.new()
  end

  defp normalize_property_key(key) when is_binary(key), do: key
  defp normalize_property_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_property_key(key), do: to_string(key)
end
