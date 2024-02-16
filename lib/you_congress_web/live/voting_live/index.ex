defmodule YouCongressWeb.VotingLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings
  alias YouCongress.Votings.Voting

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()
      |> assign(:votings, Votings.list_votings(order_by: [desc: :id]))

    if connected?(socket) do
      %{assigns: %{current_user: current_user}} = socket
      YouCongress.Track.event("View Home", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Voting")
    |> assign(:voting, Votings.get_voting!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Voting")
    |> assign(:voting, %Voting{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Votings")
    |> assign(:voting, nil)
  end
end
