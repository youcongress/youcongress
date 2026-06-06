defmodule YouCongress.Countries.GeoNamesImporter do
  @moduledoc """
  Imports country records from the GeoNames countryInfo.txt dump.
  """

  alias YouCongress.Countries

  @country_info_url "https://download.geonames.org/export/dump/countryInfo.txt"

  def country_info_url, do: @country_info_url

  def download_and_import(opts \\ []) do
    url = Keyword.get(opts, :url, @country_info_url)

    with {:ok, body} <- fetch(url) do
      import_text(body)
    end
  end

  def import_text(text) when is_binary(text) do
    text
    |> parse_country_info()
    |> Enum.reduce_while({:ok, %{inserted: 0, updated: 0}}, fn attrs, {:ok, counts} ->
      case Countries.upsert_country(attrs) do
        {:ok, _country, :inserted} ->
          {:cont, {:ok, Map.update!(counts, :inserted, &(&1 + 1))}}

        {:ok, _country, :updated} ->
          {:cont, {:ok, Map.update!(counts, :updated, &(&1 + 1))}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  def parse_country_info(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.reject(&comment?/1)
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp comment?(line), do: String.starts_with?(line, "#")

  defp parse_line(line) do
    columns = String.split(line, "\t")

    with iso_alpha2 when is_binary(iso_alpha2) <- Enum.at(columns, 0),
         iso_alpha3 when is_binary(iso_alpha3) <- Enum.at(columns, 1),
         name when is_binary(name) <- Enum.at(columns, 4),
         phone_prefix when is_binary(phone_prefix) <- Enum.at(columns, 12),
         false <- blank?(iso_alpha2),
         false <- blank?(name) do
      %{
        iso_alpha2: iso_alpha2,
        iso_alpha3: iso_alpha3,
        name: name,
        phone_prefix: normalize_phone_prefix(phone_prefix)
      }
    else
      _ -> nil
    end
  end

  defp normalize_phone_prefix(value) do
    value = String.trim(value)

    cond do
      value == "" -> nil
      String.starts_with?(value, "+") -> value
      true -> "+" <> value
    end
  end

  defp blank?(value), do: String.trim(value) == ""
end
