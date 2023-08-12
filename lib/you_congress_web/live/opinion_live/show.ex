defmodule YouCongressWeb.OpinionLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:opinion, Opinions.get_opinion!(id))}
  end

  defp page_title(:show), do: "Show Opinion"
  defp page_title(:edit), do: "Edit Opinion"
end
