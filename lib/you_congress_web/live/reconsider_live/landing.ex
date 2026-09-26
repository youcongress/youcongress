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
     )
     |> assign(:page_image, url(~p"/images/social-reconsider.png"))
     |> assign(
       :page_image_alt,
       "Reconsider by YouCongress — measure how articles and videos change minds"
     )
     |> assign(:page_image_width, 1731)
     |> assign(:page_image_height, 909)}
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
          Pair an article or video with before-and-after voting on relevant YouCongress statements—
          policy proposals or claims—to see how your audience's views change.
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

      <section id="reconsider-example" aria-labelledby="reconsider-example-title" class="mt-16">
        <div class="text-center">
          <p class="text-sm font-semibold uppercase tracking-wide text-indigo-700">
            Illustrative preview
          </p>
          <h2 id="reconsider-example-title" class="mt-2 text-2xl font-bold text-gray-900">
            See a Reconsider page in action
          </h2>
          <p class="mt-2 text-gray-600">
            This static example shows what an audience member completes and what everyone sees next.
          </p>
        </div>

        <div class="mt-8 grid items-start gap-8 lg:grid-cols-2">
          <article
            id="reconsider-voting-example"
            class="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm"
          >
            <div class="border-b border-gray-200 bg-gray-50 px-5 py-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-indigo-700">
                Example voting page
              </p>
              <h3 class="mt-1 text-xl font-bold text-gray-900">
                The case for building more nuclear energy
              </h3>
              <p class="mt-1 text-sm text-gray-500">Video by Example Climate Review</p>
              <span
                id="example-video-link"
                class="mt-3 inline-flex rounded-lg border border-indigo-200 bg-white px-3 py-2 text-sm font-semibold text-indigo-700"
              >
                Watch the original video ↗
              </span>
            </div>

            <div class="space-y-5 p-5">
              <div class="rounded-xl border border-gray-200 p-4">
                <p class="font-semibold text-gray-900">
                  Nuclear energy should play a larger role in electricity generation.
                </p>

                <div class="mt-4 grid gap-4">
                  <div>
                    <p class="mb-2 text-sm font-semibold text-gray-700">Before this video</p>
                    <div class="grid grid-cols-3 gap-2 text-center text-xs font-medium">
                      <span class="rounded-lg border border-gray-200 px-2 py-2">For</span>
                      <span class="rounded-lg border border-gray-200 px-2 py-2">Abstain</span>
                      <span class="rounded-lg border border-red-600 bg-red-50 px-2 py-2 text-red-800">
                        Against
                      </span>
                    </div>
                  </div>
                  <div>
                    <p class="mb-2 text-sm font-semibold text-gray-700">Now</p>
                    <div class="grid grid-cols-3 gap-2 text-center text-xs font-medium">
                      <span class="rounded-lg border border-green-600 bg-green-50 px-2 py-2 text-green-800">
                        For
                      </span>
                      <span class="rounded-lg border border-gray-200 px-2 py-2">Abstain</span>
                      <span class="rounded-lg border border-gray-200 px-2 py-2">Against</span>
                    </div>
                  </div>
                </div>
              </div>

              <div class="rounded-xl border border-gray-200 p-4">
                <p class="font-semibold text-gray-900">Who would you trust to represent you?</p>
                <p class="mt-1 text-xs text-gray-500">Optional global delegation</p>
                <div class="mt-3 space-y-2">
                  <div
                    id="example-delegate-energy-expert"
                    class="flex items-center gap-3 rounded-lg border border-indigo-200 bg-indigo-50 p-3"
                  >
                    <span class="flex h-5 w-5 items-center justify-center rounded border border-indigo-600 bg-indigo-600 text-xs font-bold text-white">
                      ✓
                    </span>
                    <span>
                      <span class="block text-sm font-medium text-gray-900">Dr. Maya Chen</span>
                      <span class="block text-xs text-gray-500">
                        Energy expert featured in the video
                      </span>
                    </span>
                  </div>
                  <div
                    id="example-delegate-policy-researcher"
                    class="flex items-center gap-3 rounded-lg border border-gray-200 p-3"
                  >
                    <span class="h-5 w-5 rounded border border-gray-300 bg-white"></span>
                    <span>
                      <span class="block text-sm font-medium text-gray-900">Alex Rivera</span>
                      <span class="block text-xs text-gray-500">Climate policy researcher</span>
                    </span>
                  </div>
                </div>
              </div>

              <div class="rounded-lg bg-indigo-600 px-5 py-3 text-center font-semibold text-white">
                Save my response
              </div>
            </div>
          </article>

          <article
            id="reconsider-results-example"
            class="overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm"
          >
            <div class="border-b border-indigo-200 bg-indigo-50 px-5 py-5 text-center">
              <p class="text-xs font-semibold uppercase tracking-wide text-indigo-700">
                Example results
              </p>
              <p class="mt-2 text-4xl font-bold text-gray-900">75%</p>
              <p class="mt-1 text-sm text-gray-700">
                of 60 participants changed their position.
              </p>
            </div>

            <div class="space-y-5 p-5">
              <div>
                <h3 class="font-semibold text-gray-900">
                  Nuclear energy should play a larger role in electricity generation.
                </h3>
                <p class="mt-3 text-sm font-semibold text-gray-700">Community responses</p>
                <div class="mt-2 divide-y divide-gray-100 rounded-lg border border-gray-200 text-sm">
                  <div class="flex items-center gap-2 px-3 py-2">
                    <span>Against</span><span class="text-gray-400">→</span><strong>For</strong>
                    <span class="ml-auto text-gray-600">38 (63%)</span>
                  </div>
                  <div class="flex items-center gap-2 px-3 py-2">
                    <span>For</span><span class="text-gray-400">→</span><strong>For</strong>
                    <span class="ml-auto text-gray-600">10 (17%)</span>
                  </div>
                  <div class="flex items-center gap-2 px-3 py-2">
                    <span>Abstain</span><span class="text-gray-400">→</span><strong>For</strong>
                    <span class="ml-auto text-gray-600">7 (12%)</span>
                  </div>
                  <div class="flex items-center gap-2 px-3 py-2">
                    <span>Against</span><span class="text-gray-400">→</span><strong>Against</strong>
                    <span class="ml-auto text-gray-600">5 (8%)</span>
                  </div>
                </div>

                <div id="example-change-bar" class="mt-4">
                  <div class="mb-1 flex justify-between text-xs text-gray-500">
                    <span>75% reported changing</span>
                    <span>60 completed</span>
                  </div>
                  <div class="h-2 overflow-hidden rounded-full bg-gray-100">
                    <div class="h-full rounded-full bg-indigo-600" style="width: 75%"></div>
                  </div>
                </div>
              </div>

              <div class="rounded-lg border border-gray-200 p-4">
                <p class="text-sm font-semibold text-gray-900">Delegations chosen</p>
                <div class="mt-2 divide-y divide-gray-100 text-sm">
                  <div class="flex items-center gap-3 py-2">
                    <span class="font-medium">Dr. Maya Chen</span>
                    <span class="ml-auto text-gray-600">14 participants (23%)</span>
                  </div>
                  <div class="flex items-center gap-3 py-2">
                    <span class="font-medium">Alex Rivera</span>
                    <span class="ml-auto text-gray-600">9 participants (15%)</span>
                  </div>
                </div>
              </div>

              <div class="rounded-lg border border-gray-200 bg-gray-50 p-4">
                <p class="text-xs font-semibold uppercase tracking-wide text-gray-500">
                  Your response
                </p>
                <div class="mt-2 flex items-center gap-2 text-sm">
                  <span>Against</span><span class="text-gray-400">→</span><strong>For</strong>
                  <span class="ml-auto rounded-full bg-amber-100 px-2 py-1 font-semibold text-amber-800">
                    Changed
                  </span>
                </div>
              </div>
            </div>
          </article>
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
