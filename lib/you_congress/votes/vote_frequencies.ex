defmodule YouCongress.Votes.VoteFrequencies do
  @moduledoc """
  Module to calculate vote frequencies
  """

  alias YouCongress.Votes

  @spec get(number) :: %{binary => number}
  def get(voting_id) do
    vote_frequencies =
      Votes.count_by_response(voting_id)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(vote_frequencies))

    vote_frequencies
    |> Enum.map(fn {k, v} -> {k, {v, round(v * 100 / total)}} end)
    |> Enum.into(%{})
  end
end
