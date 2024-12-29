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
  alias YouCongressWeb.Tools.TimeAgo
  alias YouCongress.Halls

  @default_hall "ai"

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:search, nil)
      |> assign(:search_tab, :polls)
      |> assign(:halls, [])
      |> assign(:authors, [])
      |> assign(:votings, [])
      |> assign(:order_by_date, true)
      |> assign(:hall_name, params["hall"] || @default_hall)
      |> assign(:new_poll_visible?, false)
      |> assign(:current_user_delegation_ids, get_current_user_delegation_ids(current_user))
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
      |> assign(:page, 1)
      |> assign(:per_page, 5)
      |> assign(:has_more_votings, true)
      |> stream(:votings, [])
      |> assign_votes(1)

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
  def handle_event("load-more", _, socket) do
    {socket, _} = assign_votings(socket, socket.assigns.page + 1)
    {:noreply, socket}
  end

  def handle_event("toggle-new-poll", _, socket) do
    %{assigns: %{new_poll_visible?: new_poll_visible?}} = socket

    if Votings.votings_count_created_in_the_last_hour() > 20 do
      # Only logged users can create polls
      if socket.assigns.current_user do
        socket =
          socket
          |> assign(new_poll_visible?: !new_poll_visible?)
          |> maybe_assign_votes()

        {:noreply, socket}
      else
        {:noreply, put_flash(socket, :warning, "You need to log in to create a poll")}
      end
    else
      # Non-logged visitors can create polls
      socket =
        socket
        |> assign(new_poll_visible?: !new_poll_visible?)
        |> maybe_assign_votes()

      {:noreply, socket}
    end
  end

  def handle_event("search", %{"search" => ""}, socket) do
    socket =
      socket
      |> assign_votes(1)
      |> assign(search: nil, search_tab: nil)

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search}, socket) do
    Track.event("Search", socket.assigns.current_user)
    votings = Votings.list_votings(title_contains: search, preload: [:halls])
    authors = Authors.list_authors(search: search)
    halls = Halls.list_halls(name_contains: search)

    search_tab =
      cond do
        Enum.any?(votings) -> :polls
        Enum.any?(authors) -> :delegates
        Enum.any?(halls) -> :halls
        true -> :polls
      end

    {:noreply,
     assign(socket,
       votings: votings,
       search: search,
       search_tab: search_tab,
       authors: authors,
       halls: halls
     )}
  end

  def handle_event("search-tab", %{"tab" => "polls"}, socket) do
    {:noreply, assign(socket, search_tab: :polls)}
  end

  def handle_event("search-tab", %{"tab" => "delegates"}, socket) do
    {:noreply, assign(socket, search_tab: :delegates)}
  end

  def handle_event("search-tab", %{"tab" => "halls"}, socket) do
    {:noreply, assign(socket, search_tab: :halls)}
  end

  def handle_event("toggle-switch", _, socket) do
    order_by_date = !socket.assigns.order_by_date

    socket =
      socket
      |> assign(:order_by_date, order_by_date)
      |> assign_votes(1)

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

  defp maybe_assign_votes(%{assigns: %{new_poll_visible?: true}} = socket), do: socket
  defp maybe_assign_votes(socket), do: assign_votes(socket, 1)

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Voting")
    |> assign(:voting, %Voting{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      page_title: "YouCongress: Shape the future with Liquid Democracy and AI Twins",
      skip_page_suffix: true,
      page_description:
        "Finding agreements and understanding disagreements to improve our democracies. Open Source.",
      voting: nil
    )
  end

  defp assign_votings(socket, new_page) do
    %{
      assigns: %{
        hall_name: hall_name,
        order_by_date: order_by_date,
        per_page: per_page
      }
    } = socket

    offset = (new_page - 1) * per_page
    order = if order_by_date, do: :inserted_at_desc, else: :opinion_likes_count_desc
    args = [order: order, include_two_opinions: true, offset: offset, limit: per_page]

    args =
      case hall_name do
        "all" -> args
        _ -> Keyword.put(args, :hall_name, hall_name)
      end

    votings = Votings.list_votings(args)

    if votings == [] do
      socket = assign(socket, :has_more_votings, false)
      {socket, votings}
    else
      socket =
        socket
        |> update_votings_stream(votings, new_page)
        |> assign(:has_more_votings, true)
        |> assign(:page, new_page)

      {socket, votings}
    end
  end

  defp update_votings_stream(socket, votings, 1) do
    stream(socket, :votings, votings, reset: true)
  end

  defp update_votings_stream(socket, votings, _page) do
    stream(socket, :votings, votings)
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

  defp assign_votes(socket, page) do
    %{assigns: %{current_user: current_user}} = socket
    {socket, votings} = assign_votings(socket, page)
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
    |> assign(:votes, load_votes(voting_ids, current_user))
    |> assign(:opinions, load_opinions(voting_ids, current_user))
  end

  defp get_current_user_delegation_ids(nil), do: []

  defp get_current_user_delegation_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end
end
