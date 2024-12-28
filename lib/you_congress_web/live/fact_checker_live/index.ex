defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("analyze", %{"text" => text}, socket) do
    # Here you would integrate with your fact checking service
    # For now we'll just return random classifications
    sentences = String.split(text, ~r/[.!?]+/)

    analyzed = Enum.map(sentences, fn sentence ->
      classification = Enum.random(["fact", "opinion", "depends"])
      %{
        text: String.trim(sentence),
        classification: classification
      }
    end)

    {:noreply, assign(socket, :analyzed_text, analyzed)}
  end
end
