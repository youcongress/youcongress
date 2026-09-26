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

      <iframe
        id="substack-signup"
        src="https://youcongress.substack.com/embed"
        title="Subscribe to the YouCongress newsletter on Substack"
        class="mt-6 h-80 w-full border border-zinc-200 bg-white"
        scrolling="no"
      >
      </iframe>
    </div>
    """
  end
end
