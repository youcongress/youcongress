defmodule YouCongressWeb.VotingLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:voting, Votings.get_voting!(id))}
  end

  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"
end
