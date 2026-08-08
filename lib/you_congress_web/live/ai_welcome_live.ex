defmodule YouCongressWeb.AiWelcomeLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Track
  alias YouCongress.FeatureFlags

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    context = (socket.assigns.current_user && socket.assigns.current_user.sign_up_context) || %{}
    selected_contributions = selected_contributions(context["contribution_areas"] || [])
    launched? = FeatureFlags.enabled?(:ai_policy_launch)

    if connected?(socket) do
      Track.event("View AI Working Groups Welcome", socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "You're in | AI Working Groups")
     |> assign(:noindex, true)
     |> assign(:launched?, launched?)
     |> assign(:selected_contributions, selected_contributions)
     |> assign(:invite_url, url(~p"/ai"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      :if={!@launched?}
      class="border-b border-amber-300 bg-amber-100 px-6 py-2 text-center text-sm font-medium text-amber-900"
    >
      Private preview: please don’t post or share this page publicly before Tuesday, September 8.
      Personal invitations are welcome.
    </div>

    <div class="mx-auto max-w-2xl px-6 py-16 text-zinc-700">
      <p class="text-xs font-bold uppercase tracking-widest text-[#8f2c00]">AI Working Groups</p>
      <h1 class="mt-3 text-4xl font-extrabold tracking-tight text-zinc-900">
        You're part of the mission
      </h1>
      <p class="mt-5 text-lg leading-relaxed">
        Thanks for joining. We'll use your policy interests, experience, and preferred contribution
        areas to connect you with a small working group focused on a concrete task.
      </p>

      <div class="mt-10 rounded-2xl border border-zinc-200 bg-[#faf8f5] p-6 md:p-8">
        <h2 class="text-2xl font-bold text-zinc-900">What happens next</h2>
        <%= if @selected_contributions == [] do %>
          <p class="mt-3 leading-relaxed">
            We'll email you when there is a working group that fits your country, background, and
            interests. Each group starts with a clear task and a useful output.
          </p>
        <% else %>
          <p class="mt-3 leading-relaxed">You said you'd like to contribute in these ways:</p>
          <ul class="mt-5 space-y-4">
            <%= for {label, next_step} <- @selected_contributions do %>
              <li class="border-l-2 border-[#f0a882] pl-4">
                <p class="font-semibold text-zinc-900">{label}</p>
                <p class="mt-1 text-sm leading-relaxed text-zinc-600">{next_step}</p>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <div class="mt-8 rounded-2xl border border-zinc-200 bg-[#faf8f5] p-6 md:p-8">
        <h2 class="text-2xl font-bold text-zinc-900">Invite a friend</h2>
        <p class="mt-3 leading-relaxed">
          Working groups are stronger with a mixture of countries, professions, and practical
          skills. Invite one thoughtful person who could contribute to the mission:
        </p>
        <div class="mt-4 flex items-center gap-2 rounded-lg border border-zinc-200 bg-white">
          <pre class="m-0 flex-1 overflow-x-auto text-sm"><code id="ai-invite-url" class="block px-3 py-2">{@invite_url}</code></pre>
          <button
            type="button"
            class="shrink-0 border-l border-zinc-200 px-3 py-2 text-sm font-semibold text-brand hover:text-[#a63300]"
            data-copy-target="ai-invite-url"
            data-copy-success-label="Copied!"
            aria-label="Copy link"
          >
            Copy
          </button>
        </div>
      </div>

      <div class="mt-8 border-t border-zinc-200 pt-8">
        <h2 class="text-2xl font-bold text-zinc-900">Start exploring the evidence</h2>
        <p class="mt-3 leading-relaxed">
          Explore policy proposals and sourced public positions, cast your own votes, and delegate
          your vote to people you trust. Collected positions and participant votes remain distinct.
        </p>
        <.link
          navigate={~p"/"}
          class="mt-5 inline-block rounded-lg bg-brand px-6 py-3 font-semibold text-white hover:bg-[#a63300]"
        >
          Explore proposals and evidence
        </.link>
      </div>
    </div>
    """
  end

  defp selected_contributions(values) do
    details = %{
      "policy" =>
        {"Develop and review policies",
         "We'll connect you with proposals that need drafting, scrutiny, or cross-country perspectives."},
      "research" =>
        {"Research evidence and objections",
         "We'll point you to questions that need reliable sources, expert views, and serious counterarguments."},
      "platform" =>
        {"Improve YouCongress",
         "We'll share focused product, design, data, or engineering work that strengthens the open platform."},
      "communications" =>
        {"Writing, journalism, or communications",
         "You'll help translate supported proposals and evidence into clear material for wider audiences."},
      "outreach" =>
        {"Reach policymakers and civic organizations",
         "You'll help identify relevant people, prepare outreach, and invite public responses to supported policies."},
      "organizing" =>
        {"Facilitate and organize working groups",
         "You'll help groups start well, stay focused, and finish with a concrete result."}
    }

    values
    |> Enum.uniq()
    |> Enum.flat_map(fn value ->
      case Map.fetch(details, value) do
        {:ok, detail} -> [detail]
        :error -> []
      end
    end)
  end
end
