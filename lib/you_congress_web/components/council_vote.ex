defmodule YouCongressWeb.Components.CouncilVote do
  @moduledoc "The existing disclosure, with the ordered topic decision and each list's positions."
  use YouCongressWeb, :live_component
  alias YouCongress.Councils.Discovery

  @impl true
  def update(assigns, socket) do
    explanation = assigns.explanation
    ids = Enum.flat_map(explanation.lists, fn l -> Enum.map(l.members, & &1.author_id) end)

    {:ok,
     socket |> assign(assigns) |> assign(explanation: explanation, people: Discovery.people(ids))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <section
        id={"#{@id}-breakdown"}
        hidden={!@expanded}
        aria-labelledby="statement-council-toggle"
        class="mt-4 space-y-3 rounded-lg border border-gray-200 bg-gray-50 p-4 text-sm sm:p-6"
      >
        <h3 class="font-semibold">
          {if @explanation.answer,
            do: "Why your Council votes #{answer_label(@explanation.answer)}",
            else: "No Council majority"}
        </h3>
        <div
          :for={{list, index} <- Enum.with_index(@explanation.lists)}
          id={"#{@id}-list-#{list.id}"}
          class={[
            "rounded-lg border p-3",
            if(list.status == :deciding,
              do: "border-indigo-300 bg-indigo-50",
              else: "border-gray-200 bg-white"
            )
          ]}
        >
          <div class="flex flex-wrap justify-between gap-2">
            <strong>{index + 1}. {list.name}</strong>
            <span>{status(list)}</span>
          </div>
          <p :if={list.consulted} class="mt-1 text-gray-600">
            {list.for} For · {list.against} Against · {list.abstain} Abstain · {list.missing} no position
          </p>
          <details :if={list.consulted} open={list.status == :deciding} class="mt-2">
            <summary class="cursor-pointer text-indigo-700">People and positions</summary>
            <div class="mt-2 grid grid-cols-1 gap-3 sm:grid-cols-2">
              <section :for={answer <- [:for, :against, :abstain, nil]}>
                <h4 class="font-semibold">
                  {answer_label(answer)} ({Enum.count(list.members, &(&1.answer == answer))})
                </h4>
                <ul class="space-y-1">
                  <li :for={member <- Enum.filter(list.members, &(&1.answer == answer))}>
                    <.link
                      navigate={~p"/a/#{member.author_id}"}
                      class="text-indigo-700 hover:underline"
                    >
                      {@people[member.author_id].name || "Participant"}
                    </.link>
                  </li>
                </ul>
                <p :if={!Enum.any?(list.members, &(&1.answer == answer))} class="text-gray-500">
                  None
                </p>
              </section>
            </div>
            <p class="mt-2 text-xs text-gray-500">
              {if list.for + list.against == 0,
                do: "No For or Against positions; try the next matching list.",
                else:
                  "#{list.threshold} of #{list.for + list.against} For or Against positions needed for a majority."}
            </p>
          </details>
        </div>
        <p class="text-xs text-gray-500">
          We check matching halls in order. Every General list applies to all statements. We compare only For and Against; abstentions and missing positions do not count. A tie, or no For or Against positions, moves on to the next matching list.
        </p>
        <p class="text-xs text-gray-500">
          Only direct votes and verified sourced positions count. If no list has a majority, no Council vote is cast. Your direct vote always takes priority.
        </p>
        <.link navigate={~p"/council"} class="text-indigo-700 hover:underline">
          Edit Council order →
        </.link>
      </section>
    </div>
    """
  end

  defp answer_label(nil), do: "No position"
  defp answer_label(answer), do: answer |> to_string() |> String.capitalize()
  defp status(%{status: :unavailable}), do: "Unavailable list · Skipped"
  defp status(%{status: :not_matching}), do: "Skipped · Not a matching hall"
  defp status(%{status: :not_needed}), do: "Not needed · An earlier list decided"
  defp status(%{status: :deciding, answer: answer}), do: "Sets your vote: #{answer_label(answer)}"
  defp status(_), do: "No majority → next"
end
