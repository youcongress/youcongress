defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  alias YouCongress.DigitalTwins
  alias YouCongress.Votings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"id" => voting_id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> load_voting_and_opinions(voting_id)}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate-opinions", %{"voting_id" => voting_id}, socket) do
    send(self(), {:generate_opinion, voting_id, 3})
    {:noreply, put_flash(socket, :info, "Generating opinions...")}
  end

  @impl true
  @spec handle_info({:generate_opinion, number, number}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:generate_opinion, _voting_id, 0}, socket) do
    {:noreply, socket}
  end

  def handle_info({:generate_opinion, voting_id, n}, socket) do
    {:ok, _opinion} = DigitalTwins.generate_opinion(voting_id)

    socket =
      socket
      |> load_voting_and_opinions(voting_id)
      |> put_flash(:info, "Opinion generated")

    send(self(), {:generate_opinion, voting_id, n - 1})

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  @spec load_voting_and_opinions(Socket.t(), number) :: Socket.t()
  defp load_voting_and_opinions(socket, voting_id) do
    assign(socket, :voting, Votings.get_voting!(voting_id, include: [opinions: [:author]]))
  end
end
