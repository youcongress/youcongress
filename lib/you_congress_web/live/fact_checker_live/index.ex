defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.FactChecker
  alias YouCongress.Track

  @example_text "The Earth completes one rotation around its axis in approximately 24 hours, which gives us our day and night cycle. Many people believe that drinking hot water with lemon in the morning boosts metabolism and aids weight loss. Unicorns were commonly kept as pets by medieval European nobility until the 16th century. Studies have shown that listening to classical music while studying can improve concentration and memory retention.

The Great Wall of China is actually visible from space with the naked eye. Coffee was first discovered when Ethiopian goats started dancing after eating certain berries. The human body replaces all of its cells every seven years, making you literally a different person. Recent research suggests that dolphins have developed their own cryptocurrency system for exchanging goods and services within their pods."

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    {:ok, assign(socket, current_text: "")}
  end

  @impl true
  def handle_event("fact_check", %{"text" => ""}, socket) do
    {:noreply, socket}
  end

  def handle_event("fact_check", %{"text" => text}, socket) when is_binary(text) do
    track_event(text, socket.assigns.current_user)
    text = maybe_truncate_text(text, socket.assigns.current_user)

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

  defp maybe_truncate_text(text, current_user) do
    max_length = if current_user, do: 5000, else: 1000

    text = String.trim(text)
    initial_length = String.length(text)
    text = String.slice(text, 0, max_length)
    final_length = String.length(text)

    if final_length < initial_length do
      "#{text}..."
    else
      text
    end
  end

  defp track_event(text, current_user) do
    if text == @example_text do
      Track.event("example-fact-check", current_user)
    else
      Track.event("fact-check", current_user)
    end
  end
end
