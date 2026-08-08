defmodule YouCongressWeb.AiWelcomeLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Track

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    if connected?(socket) do
      Track.event("View AI Policy Welcome", socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "You're in | AI Policy Group")
     |> assign(:invite_url, url(~p"/ai"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border-b border-amber-300 bg-amber-100 px-6 py-2 text-center text-sm font-medium text-amber-900">
      Please don't share this link publicly. The campaign has not been launched yet.
    </div>

    <div class="mx-auto max-w-2xl px-6 py-16 text-zinc-700">
      <p class="text-xs font-bold uppercase tracking-widest text-[#8f2c00]">AI Policy Group</p>
      <h1 class="mt-3 text-4xl font-extrabold tracking-tight text-zinc-900">
        Your interest is registered
      </h1>
      <p class="mt-5 text-lg leading-relaxed">
        Thanks for joining. We'll email you when there's a pilot session that fits your country,
        background and interests.
      </p>

      <div class="mt-10 rounded-2xl border border-zinc-200 bg-[#faf8f5] p-6 md:p-8">
        <h2 class="text-2xl font-bold text-zinc-900">Invite a friend</h2>
        <p class="mt-3 leading-relaxed">
          Groups work best with a mixture of countries and professions. Invite one thoughtful
          person from a different country or profession by sharing this link:
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
        <h2 class="text-2xl font-bold text-zinc-900">Or start exploring YouCongress</h2>
        <p class="mt-3 leading-relaxed">
          Read sourced quotes from experts and public figures, vote on statements, and delegate
          your vote to people you trust.
        </p>
        <.link
          navigate={~p"/"}
          class="mt-5 inline-block rounded-lg bg-brand px-6 py-3 font-semibold text-white hover:bg-[#a63300]"
        >
          Explore YouCongress
        </.link>
      </div>
    </div>
    """
  end
end
