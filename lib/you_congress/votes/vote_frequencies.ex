defmodule YouCongress.Votes.VoteFrequencies do
  @moduledoc """
  Module to calculate vote frequencies
  """

  alias YouCongress.Votes

  @responses [:for, :abstain, :against]
  @unknown_country "Unknown country"

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

  defp frequencies(counts) do
    total = Enum.sum(Map.values(counts))

    Map.new(@responses, fn response ->
      count = Map.get(counts, response, 0)
      {response, {count, percentage(count, total)}}
    end)
  end

  defp percentage(_count, 0), do: 0
  defp percentage(count, total), do: round(count * 100 / total)
end
