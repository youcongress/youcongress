defmodule YouCongress.Councils.Evaluator do
  @moduledoc "Evaluates the saved Council majority, excluding abstentions and missing positions."

  def evaluate(lists, positions) do
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

        result =
          cond do
            for_count > against_count -> :for
            against_count > for_count -> :against
            true -> nil
          end

        trace = %{
          id: list.id,
          name: list.name,
          hall_id: list.hall_id,
          fallback: list.fallback,
          for: for_count,
          against: against_count,
          excluded: length(members) - for_count - against_count,
          consulted: is_nil(answer),
          members: members
        }

        if is_nil(answer) and result do
          {result, list.id, traces ++ [trace]}
        else
          {answer, deciding, traces ++ [trace]}
        end
      end)

    %{answer: answer, deciding_list_id: deciding, lists: traces}
  end
end
