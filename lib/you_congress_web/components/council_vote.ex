defmodule YouCongressWeb.Components.CouncilVote do
  @moduledoc "Shows the actual Council decision alongside the separate Trust 30 view."
  use YouCongressWeb, :live_component
  import YouCongressWeb.CouncilComponents
  alias YouCongress.Councils
  alias YouCongress.Councils.Discovery

  @impl true
  def update(assigns, socket) do
    explanation =
      if assigns.current_user,
        do: Councils.explain(assigns.current_user.author_id, assigns.statement.id)

    ids =
      if explanation,
        do: Enum.flat_map(explanation.lists, &Enum.map(&1.members, fn m -> m.author_id end)),
        else: []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       explanation: explanation,
       people: Discovery.people(ids),
       summary: Discovery.statement_summary(assigns.statement.id)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="council-ui mt-6 mb-6">
      <div class="yc-grid equal">
        <section class="yc-panel">
          <div class="yc-between">
            <h3>YouCongress Trust 30</h3>
            <.link navigate={~p"/trust"} class="yc-link">View list →</.link>
          </div>
          <.position_bar summary={@summary} />
          <p class="yc-help">
            Positions from {@summary.total} Trust List members. This view never changes your vote.
          </p>
          <.link :if={!@current_user} navigate={~p"/council"} class="yc-link yc-gap-sm">
            Choose your own Council →
          </.link>
        </section>
        <section :if={@explanation} id="my-council-decision" class="yc-panel tint">
          <p class="yc-eyebrow">Your vote</p>
          <h2>
            {answer(@explanation.effective)}<span :if={@explanation.direct}> · your direct vote</span>
            <span :if={!@explanation.direct && @explanation.answer}>
              · via your Council
            </span>
          </h2>
          <p :if={@explanation.direct} class="yc-help">
            Your direct vote overrides your Council on this statement.
          </p>
          <p :if={!@explanation.direct && !@explanation.answer} class="yc-help">
            No Council vote is cast when there is a tie or no eligible positions. You can vote for yourself above.
          </p>
          <p :if={!@explanation.direct && @explanation.answer} class="yc-help">
            Your Council has more {answer(@explanation.answer)} than {if @explanation.answer == :for,
              do: "Against",
              else: "For"} positions. Vote above to make your own choice.
          </p>
          <details class="yc-gap-sm">
            <summary class="cursor-pointer font-semibold">See how your Council voted</summary>
            <div :for={list <- @explanation.lists} class="yc-gap-sm">
              <div :for={member <- list.members} class="yc-voter">
                <.avatar person={@people[member.author_id]} />
                <.link
                  navigate={~p"/a/#{member.author_id}"}
                  class="yc-name"
                >
                  {@people[member.author_id].name}
                </.link>
                <span class={[
                  "yc-badge",
                  member.answer == :for && "green",
                  member.answer == :against && "red"
                ]}>
                  {answer(member.answer)}
                </span>
              </div>
              <p class="yc-help">
                {list.for} For · {list.against} Against · {list.excluded} abstaining or without an eligible position
              </p>
            </div>
            <p class="yc-help">
              Only direct votes and verified sourced positions count. Abstentions and missing positions don’t dilute the majority.
            </p>
          </details>
          <.link navigate={~p"/council?#{%{step: "pick"}}"} class="yc-link yc-gap-sm">
            Edit my Council →
          </.link>
        </section>
      </div>
    </div>
    """
  end
end
