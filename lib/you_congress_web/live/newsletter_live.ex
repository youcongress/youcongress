defmodule YouCongressWeb.NewsletterLive do
  use YouCongressWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Subscribe to YouCongress news")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-lg">
      <.header class="text-center">
        Subscribe to YouCongress news
        <:subtitle>AI governance, safety, jobs, and product updates.</:subtitle>
      </.header>

      <div class="mt-6 rounded-lg border border-zinc-200 bg-white p-6 text-center shadow-sm">
        <p class="text-sm leading-6 text-zinc-600">
          Subscriptions are managed securely by Substack.
        </p>
        <.link
          id="substack-signup"
          href="https://youcongress.substack.com/subscribe"
          target="_blank"
          rel="noopener noreferrer"
          class="mt-4 inline-flex rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:bg-indigo-500"
        >
          Subscribe on Substack
        </.link>
      </div>
    </div>
    """
  end
end
