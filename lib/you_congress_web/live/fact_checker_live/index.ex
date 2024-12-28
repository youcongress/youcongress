defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.FactChecker

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_text: "")}
  end

  @impl true
  def handle_event("fact_check", %{"text" => text}, socket) when is_binary(text) do
    case FactChecker.classify_text(text) do
      {:ok, analyzed} ->
        {:noreply,
         socket
         |> assign(:analyzed_text, analyzed)
         |> assign(:current_text, text)
         |> push_event("update_content", %{analyzed_text: analyzed})}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("fact_check", _, socket), do: {:noreply, socket}
end
