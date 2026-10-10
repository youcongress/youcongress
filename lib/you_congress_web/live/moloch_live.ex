defmodule YouCongressWeb.MolochLive do
  use YouCongressWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign_current_user(session["user_token"])
     |> assign(:page_title, "Moloch: Why We Race Toward Outcomes Nobody Wants")
     |> assign(
       :page_description,
       "What is Moloch? Explore coordination failures through an interactive AI race, learn how incentives can change, and investigate proposals on YouCongress."
     )
     |> assign(:canonical_url, url(~p"/moloch"))
     |> assign(:lab_a, "safety")
     |> assign(:lab_b, "safety")}
  end

  @impl true
  def handle_event("choose", %{"lab" => lab, "choice" => choice}, socket)
      when lab in ["a", "b"] and choice in ["safety", "speed"] do
    key = if lab == "a", do: :lab_a, else: :lab_b
    {:noreply, assign(socket, key, choice)}
  end

  def handle_event("choose", _params, socket), do: {:noreply, socket}

  defp outcome("safety", "safety") do
    %{
      title: "Stronger safeguards. Neither lab races ahead.",
      a: "Time for evaluations and safeguards; no speed disadvantage.",
      b: "Time for evaluations and safeguards; no speed disadvantage.",
      shared: "Both invest in safeguards that may reduce shared risks.",
      pressure:
        "But either lab may see an opportunity to move first by shortening its checks. Cooperation is fragile if neither can trust the other to keep it up."
    }
  end

  defp outcome("speed", "speed") do
    %{
      title: "A faster race. No clear relative winner.",
      a: "Moves faster, but Lab B does too.",
      b: "Moves faster, but Lab A does too.",
      shared:
        "Less time for safeguards may increase risks that affect everyone, including people outside the labs.",
      pressure:
        "Either lab could restore more checks, but fears falling behind if it acts alone. Both can prefer mutual safety and still feel stuck racing."
    }
  end

  defp outcome(a, _b) do
    faster = if a == "speed", do: "Lab A", else: "Lab B"
    cautious = if a == "safety", do: "Lab A", else: "Lab B"
    safety = "Keeps additional checks, but may lose ground to its competitor."
    speed = "May gain a head start by shortening checks."

    %{
      title: "#{faster} may pull ahead. #{cautious} feels the pressure.",
      a: if(a == "speed", do: speed, else: safety),
      b: if(a == "safety", do: speed, else: safety),
      shared:
        "One lab’s safeguards cannot fully protect everyone from risks created by the other.",
      pressure:
        "#{cautious} now has a reason to speed up too. #{faster} has little competitive reason to give up its head start. Good intentions alone may not hold cooperation together."
    }
  end

  attr :lab, :string, required: true
  attr :selected, :string, required: true

  defp lab_choice(assigns) do
    ~H"""
    <fieldset class="rounded-xl border border-indigo-200 bg-white p-5">
      <legend class="px-2 text-lg font-bold text-indigo-950">Lab {String.upcase(@lab)}</legend>
      <div class="grid gap-3">
        <button
          :for={
            {choice, title, description} <- [
              {"safety", "Prioritize safety",
               "Spend extra time and resources on evaluations and safeguards."},
              {"speed", "Prioritize speed", "Reduce delays to move faster than the other lab."}
            ]
          }
          id={"lab-#{@lab}-#{choice}"}
          type="button"
          phx-click="choose"
          phx-value-lab={@lab}
          phx-value-choice={choice}
          aria-pressed={to_string(@selected == choice)}
          aria-controls="race-outcome"
          class={[
            "rounded-lg border-2 p-4 text-left focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
            if(@selected == choice,
              do: "border-indigo-600 bg-indigo-50",
              else: "border-gray-200 hover:border-indigo-400"
            )
          ]}
        >
          <span class="flex items-center justify-between gap-2 font-semibold text-gray-900">
            {title}<span :if={@selected == choice} aria-hidden="true" class="text-indigo-700">✓</span>
          </span>
          <span class="mt-1 block text-sm leading-6 text-gray-600">{description}</span>
        </button>
      </div>
    </fieldset>
    """
  end
end
