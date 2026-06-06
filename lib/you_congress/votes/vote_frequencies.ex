defmodule YouCongress.Votes.VoteFrequencies do
  @moduledoc """
  Module to calculate vote frequencies
  """

  alias YouCongress.Countries
  alias YouCongress.Votes

  @responses [:for, :abstain, :against]
  @unknown_country "Unknown country"
  @country_filter_keys [:direct, :delegated, :quotes, :email_verified, :phone_verified]
  @default_country_filters Map.new(@country_filter_keys, &{&1, true})

  @spec get(number) :: %{atom => {non_neg_integer(), non_neg_integer()}}
  def get(statement_id) do
    statement_id
    |> Votes.count_by_response()
    |> Enum.into(%{})
    |> frequencies()
  end

  @spec get_by_country(number) :: [
          %{
            country_id: integer() | nil,
            country_name: String.t(),
            total_votes: non_neg_integer(),
            vote_frequencies: %{atom => {non_neg_integer(), non_neg_integer()}}
          }
        ]
  def get_by_country(statement_id) do
    statement_id
    |> Votes.count_by_country_and_response()
    |> Enum.group_by(fn {country_id, country_name, _answer, _count} ->
      {country_id, country_name || @unknown_country}
    end)
    |> Enum.map(fn {{country_id, country_name}, rows} ->
      counts =
        Map.new(rows, fn {_country_id, _country_name, answer, count} ->
          {answer, count}
        end)

      %{
        country_id: country_id,
        country_name: country_name,
        total_votes: Enum.sum(Map.values(counts)),
        vote_frequencies: frequencies(counts)
      }
    end)
    |> Enum.sort_by(fn %{country_id: country_id, country_name: country_name, total_votes: total} ->
      {is_nil(country_id), -total, country_name}
    end)
  end

  def get_by_country(statement_id, filters) do
    filters = normalize_country_filters(filters)
    countries = Countries.list_countries()

    statement_id
    |> Votes.country_result_vote_rows()
    |> Enum.filter(&include_vote?(&1, filters))
    |> Enum.group_by(&country_key(&1, filters, countries))
    |> Enum.map(fn {{country_id, country_name}, rows} ->
      counts = Enum.frequencies_by(rows, & &1.answer)

      %{
        country_id: country_id,
        country_name: country_name,
        total_votes: Enum.sum(Map.values(counts)),
        vote_frequencies: frequencies(counts)
      }
    end)
    |> sort_country_results()
  end

  def default_country_filters, do: @default_country_filters

  def normalize_country_filters(filters) when is_map(filters) do
    Map.new(@country_filter_keys, fn key ->
      {key, truthy?(Map.get(filters, key) || Map.get(filters, to_string(key)))}
    end)
  end

  def normalize_country_filters(_), do: @default_country_filters

  def toggle_country_filter(filters, filter) do
    filters = normalize_country_filters(filters)

    filter
    |> normalize_filter_key()
    |> case do
      nil -> filters
      key -> Map.update!(filters, key, &(!&1))
    end
  end

  defp frequencies(counts) do
    total = Enum.sum(Map.values(counts))

    Map.new(@responses, fn response ->
      count = Map.get(counts, response, 0)
      {response, {count, percentage(count, total)}}
    end)
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: round(count * 100 / total)

  defp include_vote?(row, filters) do
    include_vote_kind?(row, filters) && include_source?(row, filters)
  end

  defp include_vote_kind?(%{direct: true}, %{direct: include_direct}), do: include_direct

  defp include_vote_kind?(%{direct: false}, %{delegated: include_delegated}),
    do: include_delegated

  defp include_source?(%{source_url: source_url}, %{quotes: include_quotes})
       when is_binary(source_url) do
    include_quotes
  end

  defp include_source?(row, filters) do
    (filters.phone_verified && phone_verified?(row)) ||
      (filters.email_verified && email_verified?(row))
  end

  defp country_key(%{source_url: source_url} = row, _filters, _countries)
       when is_binary(source_url) do
    author_country_key(row)
  end

  defp country_key(row, %{phone_verified: true}, countries) do
    if phone_verified?(row) do
      case Countries.get_country_by_phone_number(row.user_phone_number, countries) do
        nil -> author_country_key(row)
        country -> {country.id, country.name}
      end
    else
      author_country_key(row)
    end
  end

  defp country_key(row, _filters, _countries), do: author_country_key(row)

  defp author_country_key(%{author_country_id: country_id, author_country_name: country_name}) do
    {country_id, country_name || @unknown_country}
  end

  defp email_verified?(%{user_email_confirmed: user_email_confirmed}), do: user_email_confirmed

  defp phone_verified?(%{
         user_phone_confirmed: user_phone_confirmed,
         user_phone_number: user_phone_number
       }) do
    user_phone_confirmed && is_binary(user_phone_number)
  end

  defp sort_country_results(results) do
    Enum.sort_by(results, fn %{
                               country_id: country_id,
                               country_name: country_name,
                               total_votes: total
                             } ->
      {is_nil(country_id), -total, country_name}
    end)
  end

  defp truthy?(value) when value in [true, "true", "on", "1", 1], do: true
  defp truthy?(_), do: false

  defp normalize_filter_key(filter) when is_atom(filter) and filter in @country_filter_keys,
    do: filter

  defp normalize_filter_key(filter) when is_binary(filter) do
    Enum.find(@country_filter_keys, &(to_string(&1) == filter))
  end

  defp normalize_filter_key(_), do: nil
end
