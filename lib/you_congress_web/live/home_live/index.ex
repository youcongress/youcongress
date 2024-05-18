defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votes
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.VoteComponent

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Author", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _, socket) do
    votes =
      Votes.list_votes(
        preload: [:voting, :answer, :opinion, :author],
        direct: true,
        twin: false,
        order_by: [desc: :updated_at],
        limit: 20
      )

    {:noreply,
     socket
     |> assign(page_title: "Home", votes: votes)}
  end
end
