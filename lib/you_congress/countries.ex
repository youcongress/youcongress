defmodule YouCongress.Countries do
  @moduledoc """
  The Countries context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Countries.Country
  alias YouCongress.Repo

  @country_aliases %{
    "u.s." => "US",
    "u.s.a." => "US",
    "united states of america" => "US",
    "usa" => "US",
    "us" => "US",
    "u.k." => "GB",
    "uk" => "GB",
    "gb" => "GB",
    "ca" => "CA"
  }

  def list_countries do
    Country
    |> order_by([country], asc: country.name)
    |> Repo.all()
  end

  def country_options do
    list_countries()
    |> Enum.map(fn country -> {country.name, country.id} end)
  end

  def get_country!(id), do: Repo.get!(Country, id)
  def get_country(nil), do: nil
  def get_country(""), do: nil
  def get_country(id), do: Repo.get(Country, id)

  def get_country_by_name(name) when is_binary(name) do
    normalized_name = normalize_name(name)

    Repo.one(
      from c in Country,
        where: fragment("lower(?)", c.name) == ^normalized_name
    )
  end

  def get_country_by_name(_), do: nil

  def get_country_by_iso(iso) when is_binary(iso) do
    normalized_iso = iso |> String.trim() |> String.upcase()

    Repo.one(
      from c in Country,
        where: c.iso_alpha2 == ^normalized_iso or c.iso_alpha3 == ^normalized_iso
    )
  end

  def get_country_by_iso(_), do: nil

  def get_country_by_name_or_iso(value) when is_binary(value) do
    value = String.trim(value)
    alias_or_iso = Map.get(@country_aliases, normalize_name(value), value)

    get_country_by_iso(alias_or_iso) ||
      get_country_by_name(value) ||
      get_country_by_name(alias_or_iso)
  end

  def get_country_by_name_or_iso(_), do: nil

  def create_country(attrs \\ %{}) do
    %Country{}
    |> Country.changeset(attrs)
    |> Repo.insert()
  end

  def update_country(%Country{} = country, attrs) do
    country
    |> Country.changeset(attrs)
    |> Repo.update()
  end

  def upsert_country(attrs) do
    attrs = normalize_attrs(attrs)

    existing =
      get_country_by_iso(attrs[:iso_alpha2]) ||
        get_country_by_iso(attrs[:iso_alpha3]) ||
        get_country_by_name(attrs[:name])

    case existing do
      nil ->
        attrs
        |> create_country()
        |> tag_result(:inserted)

      %Country{} = country ->
        country
        |> update_country(attrs)
        |> tag_result(:updated)
    end
  end

  def country_name(%{country: %Country{name: name}}), do: name
  def country_name(_), do: nil

  defp tag_result({:ok, country}, action), do: {:ok, country, action}
  defp tag_result({:error, changeset}, _action), do: {:error, changeset}

  defp normalize_attrs(attrs) do
    attrs
    |> Enum.map(fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
    |> Map.new()
  end

  defp normalize_key("name"), do: :name
  defp normalize_key("iso_alpha2"), do: :iso_alpha2
  defp normalize_key("iso_alpha3"), do: :iso_alpha3
  defp normalize_key("phone_prefix"), do: :phone_prefix
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: key

  defp normalize_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_value(value), do: value

  defp normalize_name(value) do
    value
    |> String.trim()
    |> String.downcase()
  end
end
