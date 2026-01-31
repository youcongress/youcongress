defmodule YouCongressWeb.StatementLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.Votes
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Track
  alias YouCongressWeb.StatementLive.Index.HallNav
  alias YouCongressWeb.StatementLive.NewFormComponent
  alias YouCongressWeb.StatementLive.FormComponent
  alias YouCongressWeb.StatementLive.Index.Search
  alias YouCongressWeb.StatementLive.CastVoteComponent
  alias YouCongressWeb.Components.SwitchComponent
  alias YouCongress.Statements.StatementQueries
  alias YouCongress.Halls
  alias YouCongressWeb.StatementLive.VoteComponent

  @default_hall "ai"

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:search, nil)
      |> assign(:search_tab, :quotes)
      |> assign(:halls, [])
      |> assign(:authors, [])
      |> assign(:quotes, [])
      |> assign(:order_by_date, true)
      |> assign(:hall_name, params["hall"] || @default_hall)
      |> assign(:new_poll_visible?, false)
      |> assign(:current_user_delegation_ids, get_current_user_delegation_ids(current_user))
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
      |> assign(:page, 1)
      |> assign(:per_page, 15)
      |> assign(:has_more_statements, true)
      |> stream(:statements, [], reset: true)
      |> assign_votes(1)

    if connected?(socket) do
      %{assigns: %{current_user: current_user}} = socket
      Track.event("View Home", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)
      |> maybe_apply_search_params(params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    {socket, _} = assign_statements(socket, socket.assigns.page + 1)
    {:noreply, socket}
  end

  def handle_event("toggle-new-poll", _, socket) do
    %{assigns: %{new_poll_visible?: new_poll_visible?}} = socket

    if Statements.statements_count_created_in_the_last_hour() > 20 do
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

  def handle_info({:voted, _vote}, socket) do
    # Component manages its own state, no need to update parent assigns
    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp maybe_assign_votes(%{assigns: %{new_poll_visible?: true}} = socket), do: socket
  defp maybe_assign_votes(socket), do: assign_votes(socket, 1)

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Statement")
    |> assign(:statement, %Statement{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      page_title:
        "AI liquid democracy polls with verifiable quotes | YouCongress",
      skip_page_suffix: true,
      page_description:
        "We gather verifiable expert quotes and use liquid democracy to surface alignment on AI governance.",
      statement: %Statement{}
    )
  end

  defp maybe_apply_search_params(socket, %{"search" => search} = params)
       when is_binary(search) and search != "" do
    socket
    |> perform_search(search)
    |> assign_tab_from_params(Map.get(params, "tab"))
  end

  defp maybe_apply_search_params(socket, _params), do: socket

  defp assign_tab_from_params(socket, tab)
       when tab in ["quotes", "delegates", "statements", "halls"] do
    assign(socket, :search_tab, String.to_existing_atom(tab))
  end

  defp assign_tab_from_params(socket, _tab), do: socket

  defp assign_statements(socket, page) do
    %{
      assigns: %{
        hall_name: hall_name,
        order_by_date: order_by_date,
        per_page: per_page
      }
    } = socket

    offset = (page - 1) * per_page
    order = if order_by_date, do: :updated_at_desc, else: :opinion_likes_count_desc
    args = [order: order, offset: offset, limit: per_page]

    args =
      case hall_name do
        "all" -> args
        _ -> Keyword.put(args, :hall_name, hall_name)
      end

    statements = Statements.list_statements(args)

    if statements == [] do
      socket = assign(socket, :has_more_statements, false)
      {socket, statements}
    else
      socket =
        socket
        |> stream(:statements, statements, reset: page == 1)
        |> assign(:has_more_statements, true)

      {socket, statements}
    end
  end

  defp load_votes(_, nil), do: %{}

  defp load_votes(statement_ids, current_user) do
    votes =
      Votes.list_votes(
        statement_ids: statement_ids,
        author_ids: [current_user.author_id],
        preload: []
      )

    Map.new(votes, fn vote ->
      {vote.statement_id, vote}
    end)
  end

  defp load_opinions(_, nil), do: %{}

  defp load_opinions(statement_ids, current_user) do
    OpinionsStatements.get_opinions_by_statement_ids(statement_ids, current_user)
  end

  defp load_delegate_ids(nil), do: []

  defp load_delegate_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end

  defp assign_votes(socket, page) do
    %{assigns: %{current_user: current_user}} = socket
    {socket, statements} = assign_statements(socket, page)
    statement_ids = Enum.map(statements, & &1.id)

    votes_by_statement_id =
      StatementQueries.get_one_vote_per_statement(
        statement_ids,
        current_user
      )

    liked_opinion_ids = Likes.get_liked_opinion_ids(current_user)

    socket
    |> assign(:delegate_ids, load_delegate_ids(current_user))
    |> assign(:votes_by_statement_id, votes_by_statement_id)
    |> assign(:liked_opinion_ids, liked_opinion_ids)
    |> assign(:votes, load_votes(statement_ids, current_user))
    |> assign(:opinions, load_opinions(statement_ids, current_user))
  end

  defp get_current_user_delegation_ids(nil), do: []

  defp get_current_user_delegation_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end

  defp perform_search(socket, search) do
    Track.event("Search", socket.assigns.current_user)
    statements = Statements.list_statements(search: search, preload: [:halls])
    authors = Authors.list_authors(search: search)
    halls = Halls.list_halls(search: search)
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
