defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Track
  alias YouCongress.Likes
  alias YouCongress.Delegations
  alias YouCongress.Votes
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongressWeb.VotingLive.CastVoteComponent

  @per_page 15

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    socket =
      socket
      |> assign(all: params["all"] == "true")
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
      |> load_opinions_and_votes()
      |> assign(
        page_title: "Home",
        page: 1
      )
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))

    {:noreply, socket}
  end

  defp load_opinions_and_votes(socket) do
    %{assigns: %{current_user: current_user, all: all}} = socket

    opinions = list_opinions(all)

    assign(socket,
      opinions: opinions,
      current_user_delegation_ids: current_user_delegation_ids(current_user),
      no_more_opinions?: length(opinions) < @per_page
    )
  end

  defp list_opinions(true) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      twin: false,
      order_by: [desc: :id],
      limit: @per_page
    )
  end

  defp list_opinions(false) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      ancestry: nil,
      order_by: :relevant,
      limit: @per_page
    )
  end

  defp list_opinions(true, offset) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      twin: false,
      order_by: [desc: :id],
      limit: @per_page,
      offset: offset
    )
  end

  defp list_opinions(false, offset) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      ancestry: nil,
      order_by: :relevant,
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
    %{assigns: %{page: page, opinions: opinions, all: all}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    new_opinions = list_opinions(all, offset)

    socket =
      assign(socket,
        opinions: opinions ++ new_opinions,
        page: new_page,
        no_more_opinions?: length(new_opinions) < @per_page
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
