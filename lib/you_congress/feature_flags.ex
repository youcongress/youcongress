defmodule YouCongress.FeatureFlags do
  @moduledoc """
  Central place to manage boolean feature flags.

  Flags default to the values in `@default_flags` and can be overridden via
  the `:feature_flags` application environment or the `FEATURE_FLAGS` env var
  (e.g. `FEATURE_FLAGS=log_in_with_x=true`).
  """

  @type flag :: :log_in_with_x

  @default_flags %{
    log_in_with_x: true
  }

  @doc """
  Returns true when the given feature flag is enabled.
  """
  @spec enabled?(flag) :: boolean()
  def enabled?(flag) when is_atom(flag) do
    Map.get(all(), flag, false)
  end

  @doc """
  Returns the map with all flags after applying runtime overrides.
  """
  @spec all() :: map()
  def all do
    Map.merge(@default_flags, overrides())
  end

  @doc """
  Parses the FEATURE_FLAGS environment variable into a map of overrides.
  Accepts comma or semicolon separated `flag=value` pairs. Unknown flags are ignored.
  """
  @spec overrides_from_env(String.t() | nil) :: map()
  def overrides_from_env(nil), do: %{}
  def overrides_from_env(""), do: %{}

  def overrides_from_env(flags) when is_binary(flags) do
    flags
    |> String.split([",", ";"], trim: true)
    |> Enum.reduce(%{}, fn entry, acc ->
      case String.split(entry, "=", parts: 2) do
        [name, value] ->
          with {:ok, flag} <- normalize_flag_name(name),
               {:ok, enabled?} <- parse_bool(value) do
            Map.put(acc, flag, enabled?)
          else
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp overrides do
    :you_congress
    |> Application.get_env(:feature_flags, %{})
    |> normalize_map()
  end

  defp normalize_flag_name(name) do
    normalized =
      name
      |> String.trim()
      |> String.replace("-", "_")

    Enum.find_value(@default_flags, fn {flag, _default} ->
      if Atom.to_string(flag) == normalized, do: {:ok, flag}
    end) || :error
  end

  defp parse_bool(value) do
    case value |> String.trim() |> String.downcase() do
      "true" -> {:ok, true}
      "1" -> {:ok, true}
      "yes" -> {:ok, true}
      "on" -> {:ok, true}
      "false" -> {:ok, false}
      "0" -> {:ok, false}
      "no" -> {:ok, false}
      "off" -> {:ok, false}
      _ -> :error
    end
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(keyword) when is_list(keyword), do: Map.new(keyword)
  defp normalize_map(_), do: %{}
end
