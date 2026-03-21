defmodule YouCongressWeb.StatementLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts.Permissions
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
  alias YouCongressWeb.AuthorLive.Show, as: AuthorShow
  alias YouCongressWeb.StatementLive.VoteComponent

  @featured_author_names [
    "Geoffrey Hinton",
    "Demis Hassabis",
    "Dario Amodei",
    "Yoshua Bengio",
    "Yann LeCun"
  ]

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    featured_authors =
      Authors.list_authors(names: @featured_author_names)
      |> order_featured_authors()

    socket =
      socket
      |> assign(:search, nil)
      |> assign(:search_tab, :quotes)
      |> assign(:halls, [])
      |> assign(:authors, [])
      |> assign(:quotes, [])
      |> assign(:order_by_date, true)
      |> assign(:hall_name, params["hall"] || HallNav.default_hall())
      |> assign(:new_poll_visible?, false)
      |> assign(:current_user_delegation_ids, get_current_user_delegation_ids(current_user))
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
      |> assign(:page, 1)
      |> assign(:per_page, 15)
      |> assign(:has_more_statements, true)
      |> assign(:editing_opinion_id, nil)
      |> assign(:can_create_statement?, Permissions.can_create_statement?(current_user))
      |> assign(:featured_authors, featured_authors)
      |> stream(:opinion_cards, [], reset: true)
      |> assign_cards(1)
      |> assign(:pending_guest_votes, %{})
      |> assign(:pending_vote_prompt, nil)
      |> assign(:show_vote_auth_modal, false)

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
    socket = assign_cards(socket, socket.assigns.page + 1)
    {:noreply, socket}
  end

  def handle_event("toggle-new-poll", _, socket) do
    %{assigns: %{new_poll_visible?: new_poll_visible?, current_user: current_user}} = socket

    if Permissions.can_create_statement?(current_user) do
      socket =
        socket
        |> assign(new_poll_visible?: !new_poll_visible?)
        |> maybe_assign_cards()

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :warning, "You don't have permission to create statements")}
    end
  end

  def handle_event("search", %{"search" => ""}, socket) do
    socket =
      socket
      |> assign_cards(1)
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

  def handle_event("close-vote-auth-modal", _, socket) do
    socket =
      socket
      |> assign(:show_vote_auth_modal, false)
      |> assign(:pending_vote_prompt, nil)

    {:noreply, socket}
  end

  def handle_event("toggle-switch", _, socket) do
    order_by_date = !socket.assigns.order_by_date

    socket =
      socket
      |> assign(:order_by_date, order_by_date)
      |> assign_cards(1)

    {:noreply, socket}
  end

  def handle_event("edit", %{"opinion_id" => opinion_id}, socket) do
    opinion_id = String.to_integer(opinion_id)

    # Find the card that contains this opinion and re-insert to force re-render
    socket =
      case find_card_by_opinion_id(socket.assigns.cards_by_id, opinion_id) do
        nil ->
          socket

        card ->
          stream_insert(socket, :opinion_cards, card)
      end

    {:noreply, assign(socket, :editing_opinion_id, opinion_id)}
  end

  def handle_event("cancel-edit", _, socket) do
    editing_opinion_id = socket.assigns.editing_opinion_id

    # Re-insert the card to force stream re-render
    socket =
      case find_card_by_opinion_id(socket.assigns.cards_by_id, editing_opinion_id) do
        nil ->
          socket

        card ->
          stream_insert(socket, :opinion_cards, card)
      end

    {:noreply, assign(socket, :editing_opinion_id, nil)}
  end

  def handle_event("update-opinion", %{"opinion_id" => opinion_id, "content" => content}, socket) do
    opinion_id = String.to_integer(opinion_id)
    opinion = Opinions.get_opinion!(opinion_id)

    if socket.assigns.current_user &&
         socket.assigns.current_user.author_id == opinion.author_id do
      case Opinions.update_opinion(opinion, %{content: content, twin: false}) do
        {:ok, _opinion} ->
          socket =
            socket
            |> assign(:editing_opinion_id, nil)
            |> assign_cards(1)
            |> put_flash(:info, "Comment updated")

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Error updating comment")}
      end
    else
      {:noreply, put_flash(socket, :error, "You can only edit your own comments")}
    end
  end

  def handle_event("delete-comment", %{"opinion_id" => opinion_id}, socket) do
    opinion_id = String.to_integer(opinion_id)
    opinion = Opinions.get_opinion!(opinion_id, preload: [:statements])

    if socket.assigns.current_user &&
         socket.assigns.current_user.author_id == opinion.author_id do
      # First, clear the opinion_id from the vote so it's preserved
      case Votes.get_vote_by_opinion_id(opinion_id) do
        nil -> :ok
        vote -> Votes.update_vote(vote, %{opinion_id: nil})
      end

      # Then delete the opinion
      {_count, nil} = Opinions.delete_opinion_and_descendants(opinion)

      socket =
        socket
        |> assign_cards(1)
        |> put_flash(:info, "Comment deleted")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "You can only delete your own comments")}
    end
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

  def handle_info({:require_auth_to_vote, payload}, socket) do
    {:noreply, record_guest_vote(socket, payload)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp order_featured_authors(authors) do
    Enum.sort_by(authors, fn author ->
      Enum.find_index(@featured_author_names, &(&1 == author.name)) || length(@featured_author_names)
    end)
  end

  defp maybe_assign_cards(%{assigns: %{new_poll_visible?: true}} = socket), do: socket
  defp maybe_assign_cards(socket), do: assign_cards(socket, 1)

  defp find_card_by_opinion_id(cards_by_id, opinion_id) do
    Enum.find_value(cards_by_id, fn {_card_id, card} ->
      cond do
        card.vote && card.vote.opinion && card.vote.opinion.id == opinion_id ->
          card

        opinion_in_votes_by_answer?(card.votes_by_answer, opinion_id) ->
          card

        true ->
          nil
      end
    end)
  end

  defp opinion_in_votes_by_answer?(votes_by_answer, opinion_id) do
    votes_by_answer
    |> Map.values()
    |> Enum.any?(fn
      %{opinion: %{id: id}} when id == opinion_id -> true
      _ -> false
    end)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Statement")
    |> assign(:statement, %Statement{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      page_title: "AI liquid democracy polls with verifiable quotes | YouCongress",
      skip_page_suffix: true,
      page_description:
        "We gather verifiable expert quotes and use liquid democracy to surface alignment on AI governance.",
      statement: %Statement{}
    )
    |> assign(:full_width, true)
    |> assign(:main_padding_classes, "px-2 pb-6 sm:px-4 lg:px-6")
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

  # For "Top" mode: show the most liked opinion for each statement (one card per statement)
  # For "New" mode: opinions ordered by most recently updated, statements can repeat
  defp assign_cards(socket, page) do
    %{
      assigns: %{
        current_user: current_user,
        hall_name: hall_name,
        order_by_date: order_by_date,
        per_page: per_page
      }
    } = socket

    offset = (page - 1) * per_page

    cards =
      if order_by_date do
        # New mode: opinions ordered by most recently updated
        StatementQueries.get_opinion_cards_by_recency(
          hall_name: hall_name,
          offset: offset,
          limit: per_page
        )
      else
        # Top mode: use the most liked opinion for each statement
        StatementQueries.get_opinion_cards_by_top_likes(
          hall_name: hall_name,
          offset: offset,
          limit: per_page
        )
      end

    if cards == [] do
      assign(socket, :has_more_statements, false)
    else
      # Extract statement IDs for loading current user's data
      statement_ids = cards |> Enum.map(& &1.statement.id) |> Enum.uniq()
      votes_by_answer = StatementQueries.get_top_votes_by_answer_for_statements(statement_ids)

      opinion_counts =
        Votes.count_by_response_map_for_statements(statement_ids, has_opinion_id: true)

      cards =
        Enum.map(cards, fn card ->
          card
          |> Map.put(:votes_by_answer, Map.get(votes_by_answer, card.statement.id, %{}))
          |> Map.put(:opinion_counts, Map.get(opinion_counts, card.statement.id, %{}))
        end)

      new_liked_opinion_ids = Likes.get_liked_opinion_ids(current_user)
      new_votes = load_votes(statement_ids, current_user)
      new_opinions = load_opinions(statement_ids, current_user)

      # Build cards_by_id for edit functionality
      new_cards_by_id = Map.new(cards, fn card -> {card.id, card} end)

      # Merge with existing data when loading additional pages
      {liked_opinion_ids, votes, opinions, cards_by_id} =
        if page == 1 do
          {new_liked_opinion_ids, new_votes, new_opinions, new_cards_by_id}
        else
          {
            Enum.uniq(socket.assigns.liked_opinion_ids ++ new_liked_opinion_ids),
            Map.merge(socket.assigns.votes, new_votes),
            Map.merge(socket.assigns.opinions, new_opinions),
            Map.merge(socket.assigns.cards_by_id, new_cards_by_id)
          }
        end

      socket
      |> stream(:opinion_cards, cards, reset: page == 1)
      |> assign(:has_more_statements, true)
      |> assign(:page, page)
      |> assign(:delegate_ids, load_delegate_ids(current_user))
      |> assign(:liked_opinion_ids, liked_opinion_ids)
      |> assign(:votes, votes)
      |> assign(:opinions, opinions)
      |> assign(:cards_by_id, cards_by_id)
    end
  end

  defp get_current_user_delegation_ids(nil), do: []

  defp get_current_user_delegation_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end

  defp order_featured_authors(authors) do
    Enum.sort_by(authors, fn author ->
      Enum.find_index(@featured_author_names, &(&1 == author.name)) ||
        length(@featured_author_names)
    end)
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
