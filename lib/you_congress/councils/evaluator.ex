defmodule YouCongress.Councils.Evaluator do
  @moduledoc "Checks matching halls in saved order; any General list applies to every statement."

  def evaluate(lists, positions, hall_ids \\ []) do
    {answer, deciding, traces} =
      Enum.reduce(lists, {nil, nil, []}, fn list, {answer, deciding, traces} ->
        members =
          Enum.map(
            list.members,
            &Map.get(positions, &1.author_id, %{
              author_id: &1.author_id,
              answer: nil,
              status: "missing",
              origin: "missing"
            })
          )

        for_count = Enum.count(members, &(&1.answer == :for))
        against_count = Enum.count(members, &(&1.answer == :against))
        threshold = div(for_count + against_count, 2) + 1
        matching = is_nil(list.hall_id) || list.hall_id in hall_ids
        consulted = matching && is_nil(answer)

        result = majority(for_count, against_count, threshold)
        status = list_status(matching, answer, result)

        trace = %{
          id: list.id,
          name: list.name,
          hall_id: list.hall_id,
          fallback: list.fallback,
          for: for_count,
          against: against_count,
          abstain: Enum.count(members, &(&1.answer == :abstain)),
          missing: Enum.count(members, &is_nil(&1.answer)),
          excluded: length(members) - for_count - against_count,
          threshold: threshold,
          matching: matching,
          consulted: consulted,
          status: status,
          answer: if(consulted, do: result),
          members: members
        }

        if consulted && result,
          do: {result, list.id, traces ++ [trace]},
          else: {answer, deciding, traces ++ [trace]}
      end)

    %{answer: answer, deciding_list_id: deciding, lists: traces}
  end

  defp majority(for_count, _, threshold) when for_count >= threshold, do: :for
  defp majority(_, against_count, threshold) when against_count >= threshold, do: :against
  defp majority(_, _, _), do: nil
  defp list_status(false, _, _), do: :not_matching
  defp list_status(_, answer, _) when not is_nil(answer), do: :not_needed
  defp list_status(_, _, nil), do: :no_majority
  defp list_status(_, _, _), do: :deciding
end
