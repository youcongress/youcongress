defmodule YouCongress.MCP.ToolUsageTracker do
  @moduledoc """
  Tracks MCP tool invocations and reports them to Amplitude.
  """

  alias Anubis.Server.Frame
  alias YouCongress.{Accounts, Amplitude}
  alias YouCongress.Accounts.User
  alias YouCongressWeb.MCPServer

  require Macro

  @event_type "MCP Tool Used"

  @doc """
  Tracks the tool invocation and returns the Accounts.get_user_by_api_key/1 result.
  """
  def track(tool_module, frame, opts \\ []) do
    key = Frame.get_query_param(frame, "key")
    user_result = opts[:user_result] || Accounts.get_user_by_api_key(key)

    user_id =
      case user_result do
        {:ok, %User{id: id}} -> id
        _ -> nil
      end

    properties =
      tool_module
      |> build_event_properties(frame, key, user_result)
      |> maybe_merge_extra(opts[:extra_properties])

    Amplitude.track_event(@event_type, user_id, properties)

    user_result
  end

  defp build_event_properties(tool_module, frame, key, user_result) do
    client_info = get_client_info(frame)

    %{
      "tool_name" => resolve_tool_name(tool_module),
      "session_id" => get_session_id(frame),
      "client_name" => Map.get(client_info, "name"),
      "client_version" => Map.get(client_info, "version"),
      "used_api_key" => match?({:ok, %User{}}, user_result),
      "api_key_present" => key_present?(key)
    }
    |> drop_nil_values()
  end

  defp drop_nil_values(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp maybe_merge_extra(properties, nil), do: properties

  defp maybe_merge_extra(properties, extra) when is_map(extra) do
    extra
    |> drop_nil_values()
    |> Enum.reduce(properties, fn {key, value}, acc ->
      Map.put(acc, normalize_property_key(key), value)
    end)
  end

  defp maybe_merge_extra(properties, _extra), do: properties

  defp normalize_property_key(key) when is_binary(key), do: key
  defp normalize_property_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_property_key(key), do: to_string(key)

  defp resolve_tool_name(tool_module) do
    MCPServer.__components__(:tool)
    |> Enum.find_value(fn
      %{handler: ^tool_module, name: name} -> name
      _ -> nil
    end)
    |> case do
      nil ->
        tool_module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      name ->
        name
    end
  end

  defp get_session_id(%Frame{} = frame), do: Frame.get_mcp_session_id(frame)
  defp get_session_id(_frame), do: nil

  defp get_client_info(%Frame{} = frame) do
    frame
    |> Frame.get_client_info()
    |> normalize_map_keys()
  end

  defp get_client_info(_frame), do: %{}

  defp normalize_map_keys(nil), do: %{}

  defp normalize_map_keys(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, normalize_property_key(key), value)
    end)
  end

  defp normalize_map_keys(_map), do: %{}

  defp key_present?(key) when is_binary(key), do: String.trim(key) != ""
  defp key_present?(_key), do: false
end
