defmodule YouCongressWeb.VotingLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors
  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongressWeb.VotingLive.Index.HallNav
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.NewFormComponent
  alias YouCongressWeb.VotingLive.FormComponent
  alias YouCongressWeb.VotingLive.Index.Search

  @default_hall "ai"

  @impl true
  def mount(params, session, socket) do
    votings = load_votings(params["hall"])

    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign(:search, nil)
      |> assign(:search_tab, :polls)
      |> assign(
        votings: votings,
        hall_name: params["hall"] || @default_hall,
        new_poll_visible?: false
      )

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
    votings = load_votings(socket.assigns.hall_name)

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
      page_title: "YouCongress: Find agreement, understand disagreement.",
      skip_page_suffix: true,
      page_description: "Polls, Liquid Democracy + AI Digital Twins.",
      voting: nil
    )
  end

  defp load_votings(hall_name) do
    if hall_name != "all" do
      Votings.list_votings(
        hall_name: hall_name || @default_hall,
        order: :desc,
        preload: [:halls]
      )
    else
      Votings.list_votings(order: :desc, preload: [:halls])
    end
  end
end
