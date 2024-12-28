defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  import Logger

  alias YouCongress.FactChecker
  alias YouCongress.Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_text: "", loading: false)}
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

      {:error, error} ->
        Logger.error("Fact checker error: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error analyzing text")}
    end
  end

  def handle_event("fact_check", _, socket), do: {:noreply, socket}
end
