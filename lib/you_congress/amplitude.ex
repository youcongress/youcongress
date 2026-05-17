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
  def track_event(event_type, user_id, event_properties \\ %{})

  def track_event(event_type, user_id, event_properties) do
    track_event(event_type, user_id, event_properties, [])
  end

  def track_event(event_type, user_id, event_properties, opts) do
    if enabled?() do
      args =
        %{
          "event_type" => event_type,
          "user_id" => normalize_user_id(user_id),
          "event_properties" => normalize_properties(event_properties),
          "device_id" => normalize_device_id(Keyword.get(opts, :device_id))
        }
        |> drop_nil_values()

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
  def deliver_event(event_type, user_id, event_properties \\ %{})

  def deliver_event(event_type, user_id, event_properties) do
    deliver_event(event_type, user_id, event_properties, [])
  end

  def deliver_event(event_type, user_id, event_properties, opts) do
    case Application.get_env(:you_congress, :amplitude_api_key) do
      key when is_binary(key) and key != "" ->
        payload =
          %{
            "api_key" => key,
            "events" => [build_event(event_type, user_id, event_properties, opts)]
          }

        headers = [{"Content-Type", "application/json"}, {"Accept", "*/*"}]

        :post
        |> Finch.build(@api_url, headers, Jason.encode!(payload))
        |> Finch.request(Swoosh.Finch)
        |> normalize_delivery_result()

      _ ->
        :ok
    end
  end

  defp build_event(event_type, user_id, event_properties, opts) do
    %{
      "event_type" => event_type,
      "user_id" => normalize_user_id(user_id),
      "event_properties" => normalize_properties(event_properties)
    }
    |> maybe_put("device_id", normalize_device_id(Keyword.get(opts, :device_id)))
  end

  defp normalize_user_id(nil), do: nil
  defp normalize_user_id(user_id) when is_binary(user_id), do: user_id
  defp normalize_user_id(user_id), do: to_string(user_id)

  defp normalize_device_id(nil), do: nil
  defp normalize_device_id(device_id) when is_binary(device_id), do: device_id
  defp normalize_device_id(device_id), do: to_string(device_id)

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

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_delivery_result({:ok, %Finch.Response{status: status} = response})
       when status in 200..299 do
    {:ok, response}
  end

  defp normalize_delivery_result({:ok, %Finch.Response{} = response}) do
    {:error, response}
  end

  defp normalize_delivery_result(result), do: result
end
