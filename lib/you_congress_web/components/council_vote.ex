defmodule YouCongressWeb.Components.CouncilVote do
  @moduledoc "A collapsed breakdown of the members behind a Council vote."
  use YouCongressWeb, :live_component
  alias YouCongress.Councils
  alias YouCongress.Councils.Discovery

  @impl true
  def update(assigns, socket) do
    explanation = Councils.explain(assigns.current_user.author_id, assigns.statement.id)
    members = Enum.flat_map(explanation.lists, & &1.members)

    groups =
      for answer <- [:for, :against, :abstain] do
        %{
          answer: answer,
          label: answer |> to_string() |> String.capitalize(),
          members: Enum.filter(members, &(&1.answer == answer))
        }
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       groups: groups,
       people: Discovery.people(Enum.map(members, & &1.author_id)),
       missing: Enum.count(members, &is_nil(&1.answer))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <details id={"#{@id}-breakdown"} class="group text-sm">
        <summary class="cursor-pointer text-indigo-700 underline underline-offset-2 hover:text-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-indigo-600">
          See how your Council voted
        </summary>
        <div class="mt-3 space-y-4 rounded-lg border border-gray-200 bg-gray-50 p-4">
          <section
            :for={group <- @groups}
            id={"#{@id}-#{group.answer}"}
            aria-labelledby={"#{@id}-#{group.answer}-heading"}
          >
            <h3 id={"#{@id}-#{group.answer}-heading"} class="font-semibold text-gray-900">
              {group.label} <span class="font-normal text-gray-500">({length(group.members)})</span>
            </h3>
            <ul :if={group.members != []} class="mt-1 space-y-1">
              <li :for={member <- group.members}>
                <.link
                  navigate={~p"/a/#{member.author_id}"}
                  class="break-words text-indigo-700 hover:underline"
                >
                  {@people[member.author_id].name || "Participant"}
                </.link>
              </li>
            </ul>
            <p :if={group.members == []} class="mt-1 text-gray-500">No Council members.</p>
          </section>
          <p :if={@missing > 0} class="text-xs text-gray-500">
            {@missing} {if @missing == 1, do: "member has", else: "members have"} no eligible position on this statement.
          </p>
          <p class="text-xs text-gray-500">
            Only direct votes and verified sourced positions count. Abstentions do not count toward the majority.
          </p>
        </div>
      </details>
    </div>
    """
  end
end
