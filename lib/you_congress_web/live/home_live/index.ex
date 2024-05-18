defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votes
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.AuthorLive.Show, as: AuthorShow

  @per_page 15

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Activity", socket.assigns.current_user)
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
        limit: @per_page
      )

    socket =
      socket
      |> stream(:votes, votes)
      |> assign(page_title: "Home", page: 1, no_more_votes?: length(votes) < @per_page)

    {:noreply, socket}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    %{assigns: %{page: page}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    votes =
      Votes.list_votes(
        preload: [:voting, :answer, :opinion, :author],
        direct: true,
        twin: false,
        order_by: [desc: :updated_at],
        limit: @per_page,
        offset: offset
      )

    socket =
      socket
      |> stream(:votes, votes)
      |> assign(page: new_page, no_more_votes?: length(votes) < @per_page)

    {:noreply, socket}
  end
end
