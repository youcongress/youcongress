defmodule YouCongressWeb.ReconsiderLive.Landing do
  use YouCongressWeb, :live_view

  @contact_subject "Reconsider beta access"
  @contact_body """
  Hi YouCongress team,

  I'd like to try Reconsider for an article or video.

  My publication or channel:
  Link:
  What I'd like to test:
  """

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign_current_user(session["user_token"])
     |> assign(:page_title, "Reconsider — measure how minds change")
     |> assign(:canonical_url, url(~p"/reconsider"))
     |> assign(
       :page_description,
       "Pair an article or video with before-and-after voting to see how your audience's views change."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-5xl px-4 py-10 sm:px-6 sm:py-16">
      <section class="mx-auto max-w-3xl text-center">
        <span class="inline-flex rounded-full bg-amber-100 px-3 py-1 text-sm font-semibold text-amber-800">
          Beta
        </span>
        <h1 class="mt-5 text-4xl font-bold tracking-tight text-gray-900 sm:text-5xl">
          Discover whether your content changes minds
        </h1>
        <p class="mx-auto mt-6 max-w-2xl text-lg leading-8 text-gray-600">
          Reconsider lets your readers or viewers record what they believed before your article or
          video, what they believe now, and optionally who they trust to represent them.
        </p>
        <div class="mt-8 flex flex-wrap items-center justify-center gap-3">
          <.link
            id="reconsider-beta-contact"
            href={beta_contact_path()}
            class="rounded-lg bg-indigo-600 px-5 py-3 text-base font-semibold text-white shadow-sm hover:bg-indigo-500"
          >
            Ask to try Reconsider
          </.link>
          <.link
            :if={
              @current_user &&
                YouCongress.Accounts.Permissions.can_create_reconsideration?(@current_user)
            }
            href={~p"/reconsider/new"}
            class="rounded-lg border border-gray-300 bg-white px-5 py-3 text-base font-semibold text-gray-800 hover:bg-gray-50"
          >
            Create a Reconsider page
          </.link>
        </div>
      </section>

      <section aria-labelledby="how-reconsider-works" class="mt-16">
        <h2 id="how-reconsider-works" class="text-center text-2xl font-bold text-gray-900">
          How it works
        </h2>
        <div class="mt-8 grid gap-5 md:grid-cols-3">
          <article class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <span class="flex h-9 w-9 items-center justify-center rounded-full bg-indigo-100 font-bold text-indigo-700">
              1
            </span>
            <h3 class="mt-4 text-lg font-semibold text-gray-900">Choose what to reconsider</h3>
            <p class="mt-2 text-sm leading-6 text-gray-600">
              Add your article or video, select up to three YouCongress statements, and optionally
              include people featured in the content.
            </p>
          </article>

          <article class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <span class="flex h-9 w-9 items-center justify-center rounded-full bg-indigo-100 font-bold text-indigo-700">
              2
            </span>
            <h3 class="mt-4 text-lg font-semibold text-gray-900">Invite one quick response</h3>
            <p class="mt-2 text-sm leading-6 text-gray-600">
              Your audience records its before and now positions in one form. Participants may also
              delegate their future votes to people they trust.
            </p>
          </article>

          <article class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <span class="flex h-9 w-9 items-center justify-center rounded-full bg-indigo-100 font-bold text-indigo-700">
              3
            </span>
            <h3 class="mt-4 text-lg font-semibold text-gray-900">See the shared result</h3>
            <p class="mt-2 text-sm leading-6 text-gray-600">
              See how many people changed their minds, every before-to-now combination, and which
              featured people participants chose as delegates.
            </p>
          </article>
        </div>

        <div class="mt-6 rounded-xl border border-indigo-100 bg-indigo-50 p-5 text-center">
          <h3 class="font-semibold text-gray-900">Connected to the rest of YouCongress</h3>
          <p class="mx-auto mt-2 max-w-3xl text-sm leading-6 text-gray-600">
            Each participant’s “now” positions become their regular YouCongress votes. Anyone they
            select is added to their global delegation list, while the before-and-after record
            stays attached to this Reconsider page.
          </p>
        </div>
      </section>

      <section class="mt-16 rounded-2xl bg-indigo-50 px-6 py-10 text-center sm:px-10">
        <p class="text-sm font-semibold uppercase tracking-wide text-indigo-700">Currently in beta</p>
        <h2 class="mt-2 text-2xl font-bold text-gray-900">Want to try it with your audience?</h2>
        <p class="mx-auto mt-3 max-w-2xl text-gray-600">
          Tell us about your publication, channel, article, or video. We’ll help you set up an early
          Reconsider page and learn from the experience.
        </p>
        <.link
          id="reconsider-beta-contact-secondary"
          href={beta_contact_path()}
          class="mt-6 inline-flex rounded-lg bg-indigo-600 px-5 py-3 font-semibold text-white hover:bg-indigo-500"
        >
          Contact YouCongress
        </.link>
      </section>
    </main>
    """
  end

  defp beta_contact_path do
    ~p"/contact?#{%{subject: @contact_subject, body: @contact_body}}"
  end
end
