defmodule YouCongressWeb.FactCheckerLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.FactChecker

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
end
