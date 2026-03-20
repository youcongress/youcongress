defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors
  alias YouCongress.Halls
  alias YouCongress.Opinions
  alias YouCongress.FeatureFlags
  alias YouCongress.Track
  alias YouCongress.Statements
  alias YouCongressWeb.StatementLive.Index.Search

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(
        :page_title,
        "AI Safety & Governance liquid democracy polls with verifiable quotes | YouCongress"
      )
      |> assign(
        :page_description,
        "We gather verifiable quotes and use liquid democracy to surface alignment on AI governance."
      )
      |> assign(:skip_page_suffix, true)
      |> assign(:live_action, :new)
      |> assign(:current_user, current_user)
      |> assign(:page, :home)
      |> assign(:search, nil)
      |> assign(:search_tab, :quotes)
      |> assign(:halls, [])
      |> assign(:authors, [])
      |> assign(:statements, [])
      |> assign(:quotes, [])
      |> assign(:log_in_with_x_enabled, FeatureFlags.enabled?(:log_in_with_x))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      if search = params["search"] do
        socket
        |> perform_search(search)
        |> assign_tab(params["tab"])
      else
        socket
      end

    {:noreply, socket}
  end

  defp assign_tab(socket, nil), do: socket

  defp assign_tab(socket, tab) do
    assign(socket, :search_tab, String.to_existing_atom(tab))
  rescue
    _ -> socket
  end

  @impl true
  def handle_event("search", %{"search" => ""}, socket) do
    socket =
      socket
      |> assign(search: nil, search_tab: nil)

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, perform_search(socket, search)}
  end

  def handle_event("search-tab", %{"tab" => "statements"}, socket) do
    {:noreply, assign(socket, search_tab: :statements)}
  end

  def handle_event("search-tab", %{"tab" => "delegates"}, socket) do
    {:noreply, assign(socket, search_tab: :delegates)}
  end

  def handle_event("search-tab", %{"tab" => "halls"}, socket) do
    {:noreply, assign(socket, search_tab: :halls)}
  end

  def handle_event("search-tab", %{"tab" => "quotes"}, socket) do
    {:noreply, assign(socket, search_tab: :quotes)}
  end

  defp perform_search(socket, search) do
    Track.event("Search via Home", socket.assigns.current_user)
    statements = Statements.list_statements(search: search, preload: [:halls])
    authors = Authors.list_authors(search: search)
    halls = Halls.list_halls(name_contains: search)
    quotes = Opinions.list_opinions(search: search, preload: [:author])

    search_tab =
      cond do
        Enum.any?(quotes) -> :quotes
        Enum.any?(authors) -> :delegates
        Enum.any?(statements) -> :statements
        Enum.any?(halls) -> :halls
        true -> :quotes
      end

    assign(socket,
      statements: statements,
      search: search,
      search_tab: search_tab,
      authors: authors,
      halls: halls,
      quotes: quotes
    )
  end
end
