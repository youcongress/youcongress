defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  @max_text_length 3000

  import Logger

  alias YouCongress.FactChecker
  alias YouCongress.Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, current_text: "")}
  end

  @impl true
  def handle_event("fact_check", %{"text" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("fact_check", %{"text" => text}, socket) when is_binary(text) do
    text = maybe_truncate_text(text)

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

  defp maybe_truncate_text(text) do
    text = String.trim(text)
    initial_length = String.length(text)
    text = String.slice(text, 0, @max_text_length)
    final_length = String.length(text)
    text = if final_length < initial_length, do: "#{text}...", else: text
  end
end
