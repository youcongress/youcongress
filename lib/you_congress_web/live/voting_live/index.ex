defmodule YouCongressWeb.VotingLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongress.Votes
  alias YouCongress.Opinions
  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.DigitalTwins.Regenerate
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.Index.HallNav
  alias YouCongressWeb.VotingLive.NewFormComponent
  alias YouCongressWeb.VotingLive.FormComponent
  alias YouCongressWeb.VotingLive.Index.Search
  alias YouCongressWeb.VotingLive.CastVoteComponent
  alias YouCongressWeb.Components.SwitchComponent
  alias YouCongress.Votings.VotingQueries

  @default_hall "ai"

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    socket =
      socket
      |> assign(:search, nil)
      |> assign(:search_tab, :polls)
      |> assign(:order_by_date, false)
      |> assign(:hall_name, params["hall"] || @default_hall)
      |> assign(:new_poll_visible?, false)
      |> assign_votes()

    if connected?(socket) do
      %{assigns: %{current_user: current_user}} = socket
      Track.event("View Home", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("toggle-new-poll", _, socket) do
    %{assigns: %{current_user: current_user, new_poll_visible?: new_poll_visible?}} = socket

    if current_user do
      {:noreply, assign(socket, new_poll_visible?: !new_poll_visible?)}
    else
      {:noreply, put_flash(socket, :error, "You need to log in to create a poll")}
    end
  end

  def handle_event("search", %{"search" => ""}, socket) do
    votings = load_votings(socket.assigns.hall_name, socket.assigns.order_by_date)

    {:noreply, assign(socket, votings: votings, search: nil, search_tab: nil)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    Track.event("Search", socket.assigns.current_user)
    votings = Votings.list_votings(title_contains: search, preload: [:halls])
    authors = Authors.list_authors(search: search)

    search_tab = socket.assigns.search_tab

    search_tab =
      cond do
        search_tab == :polls && Enum.any?(votings) -> :polls
        Enum.any?(authors) -> :delegates
        true -> :polls
      end

    {:noreply,
     assign(socket,
       votings: votings,
       search: search,
       search_tab: search_tab,
       authors: authors
     )}
  end

  def handle_event("search-tab", %{"tab" => "polls"}, socket) do
    {:noreply, assign(socket, search_tab: :polls)}
  end

  def handle_event("search-tab", %{"tab" => "delegates"}, socket) do
    {:noreply, assign(socket, search_tab: :delegates)}
  end

  def handle_event("toggle-order-by-date", _, socket) do
    order_by_date = !socket.assigns.order_by_date

    socket =
      socket
      |> assign(:order_by_date, order_by_date)
      |> assign_votes()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info({:regenerate, opinion_id}, socket) do
    %{assigns: %{current_user: current_user, votes_by_voting_id: votes_by_voting_id}} = socket

    case Regenerate.regenerate(opinion_id, current_user) do
      {:ok, {_, vote}} ->
        vote = Votes.get_vote(vote.id, preload: [:answer, :opinion, :author])
        votes_by_voting_id = Map.put(votes_by_voting_id, vote.voting_id, vote)

        socket =
          socket
          |> assign(:votes_by_voting_id, votes_by_voting_id)
          |> assign(:regenerating_opinion_id, nil)
          |> put_flash(:info, "Opinion regenerated.")

        {:noreply, socket}

      error ->
        Logger.debug("Error regenerating opinion. #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error regenerating opinion.")}
    end
  end

  def handle_info(_, socket), do: {:noreply, socket}

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
    |> assign(
      page_title: "YouCongress: Shape the future with Smart Polls.",
      skip_page_suffix: true,
      page_description:
        "Finding common ground through liquid democracy and AI twins. Open Source.",
      voting: nil
    )
  end

  defp load_votings(hall_name, order_by_date) do
    order = if order_by_date, do: :inserted_at_desc, else: :updated_at_desc

    if hall_name != "all" do
      Votings.list_votings(
        hall_name: hall_name || @default_hall,
        order: order
      )
    else
      Votings.list_votings(order: order)
    end
  end

  defp load_votes(_, nil), do: %{}

  defp load_votes(voting_ids, current_user) do
    votes =
      Votes.list_votes(
        voting_ids: voting_ids,
        author_ids: [current_user.author_id],
        preload: [:answer]
      )

    Map.new(votes, fn vote ->
      {vote.voting_id, vote}
    end)
  end

  defp load_opinions(_, nil), do: %{}

  defp load_opinions(voting_ids, current_user) do
    opinions =
      Opinions.list_opinions(
        voting_ids: voting_ids,
        author_ids: [current_user.author_id]
      )

    Map.new(opinions, fn opinion ->
      {opinion.voting_id, opinion}
    end)
  end

  defp load_delegate_ids(nil), do: []

  defp load_delegate_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end

  defp assign_votes(socket) do
    %{assigns: %{current_user: current_user, hall_name: hall_name}} = socket

    votings = load_votings(hall_name, socket.assigns.order_by_date)
    voting_ids = Enum.map(votings, & &1.id)

    votes_by_voting_id =
      VotingQueries.get_one_vote_per_voting(
        voting_ids,
        current_user
      )

    liked_opinion_ids = Likes.get_liked_opinion_ids(current_user)

    socket
    |> assign(:delegate_ids, load_delegate_ids(current_user))
    |> assign(:votes_by_voting_id, votes_by_voting_id)
    |> assign(:liked_opinion_ids, liked_opinion_ids)
    |> assign(:votings, votings)
    |> assign(:votes, load_votes(voting_ids, current_user))
    |> assign(:opinions, load_opinions(voting_ids, current_user))
  end
end
