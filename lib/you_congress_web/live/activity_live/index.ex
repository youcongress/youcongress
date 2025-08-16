defmodule YouCongressWeb.ActivityLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Track
  alias YouCongress.Likes
  alias YouCongress.Delegations
  alias YouCongress.Votes
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongressWeb.VotingLive.CastVoteComponent
  alias YouCongressWeb.Components.SwitchComponent

  @per_page 15

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    socket =
      socket
      |> assign(
        :current_user_votes_by_voting_id,
        get_current_user_votes_by_voting_id(socket.assigns.current_user)
      )

    if connected?(socket) do
      Track.event("View Activity", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _, socket) do
    %{assigns: %{current_user: current_user}} = socket

    socket =
      socket
      |> assign(:include_opinions_from_twins, false)
      |> load_opinions_and_votes()
      |> assign(
        page_title: "Activity",
        page: 1
      )
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))

    {:noreply, socket}
  end

  defp load_opinions_and_votes(socket) do
    %{assigns: %{current_user: current_user}} = socket

    opinions = list_opinions(socket)

    assign(socket,
      opinions: opinions,
      current_user_delegation_ids: current_user_delegation_ids(current_user),
      no_more_opinions?: length(opinions) < @per_page
    )
  end

  defp list_opinions(socket) do
    Opinions.list_opinions(
      preload: [:votings, :author],
      include_twins: socket.assigns.include_opinions_from_twins,
      order_by: [desc: :id],
      limit: @per_page
    )
  end

  defp list_opinions(socket, offset) do
    Opinions.list_opinions(
      preload: [:votings, :author],
      include_twins: socket.assigns.include_opinions_from_twins,
      order_by: [desc: :id],
      limit: @per_page,
      offset: offset
    )
  end

  defp current_user_delegation_ids(nil), do: []

  defp current_user_delegation_ids(%{author_id: current_user_author_id}) do
    Delegations.list_delegation_ids(deleguee_id: current_user_author_id)
  end

  @impl true
  def handle_event("load-more", _, socket) do
    %{assigns: %{page: page, opinions: opinions}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    new_opinions = list_opinions(socket, offset)

    socket =
      assign(socket,
        opinions: opinions ++ new_opinions,
        page: new_page,
        no_more_opinions?: length(new_opinions) < @per_page
      )

    {:noreply, socket}
  end

  def handle_event("toggle-switch", _, socket) do
    %{assigns: %{include_opinions_from_twins: include_opinions_from_twins}} = socket

    socket =
      socket
      |> assign(:include_opinions_from_twins, !include_opinions_from_twins)
      |> load_opinions_and_votes()
      |> assign(
        page_title: "Activity",
        page: 1
      )

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

  def handle_info(_, socket), do: {:noreply, socket}

  def get_current_user_votes_by_voting_id(nil), do: %{}

  def get_current_user_votes_by_voting_id(current_user) do
    [author_ids: [current_user.author_id], preload: [:answer]]
    |> Votes.list_votes()
    |> Enum.reduce(%{}, fn vote, acc -> Map.put(acc, vote.voting_id, vote) end)
  end
end
