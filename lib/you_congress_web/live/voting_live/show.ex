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
     |> load_voting_and_votes(voting_id)}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate-votes", %{"voting_id" => voting_id}, socket) do
    voting_id = String.to_integer(voting_id)
    send(self(), {:generate_vote, voting_id, 3})
    {:noreply, put_flash(socket, :info, "Generating votes...")}
  end

  @impl true
  @spec handle_info({:generate_vote, number, number}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:generate_vote, _voting_id, 0}, socket) do
    {:noreply, socket}
  end

  def handle_info({:generate_vote, voting_id, n}, socket) do
    {:ok, _vote} = DigitalTwins.generate_vote(voting_id)

    socket =
      socket
      |> load_voting_and_votes(voting_id)
      |> put_flash(:info, "Vote generated")

    send(self(), {:generate_vote, voting_id, n - 1})

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  @spec load_voting_and_votes(Socket.t(), number) :: Socket.t()
  defp load_voting_and_votes(socket, voting_id) do
    assign(
      socket,
      :voting,
      Votings.get_voting!(voting_id, include: [votes: [:author, :answer]])
    )
  end

  defp response(assigns, response) do
    assigns =
      assign(assigns, color: response_color(response), response: String.downcase(response))

    ~H"""
    <span class={"#{@color} font-bold"}>
      <%= @response %>
    </span>
    """
  end

  defp response_color("Agree"), do: "text-green-800"
  defp response_color("Strongly agree"), do: "text-green-800"
  defp response_color("Disagree"), do: "text-red-800"
  defp response_color("Strongly disagree"), do: "text-red-800"
  defp response_color("Abstain"), do: "text-gray-400"
  defp response_color("N/A"), do: "text-gray-400"
end
