defmodule YouCongressWeb.QuoteReviewLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Halls
  import YouCongressWeb.Tools.TimeAgo

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    halls_with_pending_quotes = Halls.list_halls_with_pending_quotes()

    {:ok,
     socket
     |> assign(:page_title, "Review Quotes")
     |> assign(:pending_quotes, [])
     |> assign(:page, 1)
     |> assign(:per_page, 20)
     |> assign(:has_more, true)
     |> assign(:editing_quote_id, nil)
     |> assign(:sort_by, :desc)
     |> assign(:selected_hall, nil)
     |> assign(:halls, halls_with_pending_quotes)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, load_pending_quotes(socket, 1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    {:noreply, load_pending_quotes(socket, socket.assigns.page + 1)}
  end

  def handle_event("verify", %{"id" => id}, socket) do
    opinion = Opinions.get_opinion!(String.to_integer(id))

    verifier_id = socket.assigns.current_user && socket.assigns.current_user.id

    case Opinions.update_opinion(opinion, %{
           verified_at: DateTime.utc_now(),
           verified_by_user_id: verifier_id
         }) do
      {:ok, _} ->
        {:noreply, remove_from_list(socket, opinion.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to verify quote")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    opinion = Opinions.get_opinion!(String.to_integer(id))

    case Opinions.delete_opinion(opinion) do
      {:ok, _} ->
        {:noreply, remove_from_list(socket, opinion.id)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete quote")}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    quote_id = String.to_integer(id)
    {:noreply, assign(socket, :editing_quote_id, quote_id)}
  end

  def handle_event("toggle-sort", _params, socket) do
    new_sort_by = if socket.assigns.sort_by == :desc, do: :asc, else: :desc

    {:noreply,
     socket
     |> assign(:sort_by, new_sort_by)
     |> assign(:pending_quotes, [])
     |> assign(:page, 1)
     |> load_pending_quotes(1)}
  end

  def handle_event("filter-hall", params, socket) do
    hall_name = params["hall"] || params["value"]

    selected_hall = if hall_name == "", do: nil, else: hall_name

    {:noreply,
     socket
     |> assign(:selected_hall, selected_hall)
     |> assign(:pending_quotes, [])
     |> assign(:page, 1)
     |> load_pending_quotes(1)}
  end

  @impl true
  def handle_info({:opinion_updated, updated_opinion}, socket) do
    # Update the quote in the list
    updated_quotes = update_quote_in_list(socket.assigns.pending_quotes, updated_opinion)

    {:noreply,
     socket
     |> assign(:pending_quotes, updated_quotes)
     |> assign(:editing_quote_id, nil)
     |> put_flash(:info, "Quote updated successfully")}
  end

  def handle_info({:opinion_update_error, _changeset}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to update quote")}
  end

  def handle_info(:opinion_edit_cancelled, socket) do
    {:noreply, assign(socket, :editing_quote_id, nil)}
  end

  defp remove_from_list(socket, id) do
    list = Enum.reject(socket.assigns.pending_quotes, &(&1.id == id))
    assign(socket, :pending_quotes, list)
  end

  defp load_pending_quotes(socket, page) do
    %{assigns: %{per_page: per_page, sort_by: sort_by, selected_hall: selected_hall}} = socket
    offset = (page - 1) * per_page

    opts = [
      only_quotes: true,
      is_verified: false,
      order_by: [{sort_by, :id}],
      limit: per_page,
      offset: offset,
      preload: [:author, :statements]
    ]

    opts = if selected_hall, do: Keyword.put(opts, :hall_name, selected_hall), else: opts

    quotes = Opinions.list_opinions(opts)

    # Load author votes for each quote's statements
    quotes_with_votes = load_author_votes_for_quotes(quotes)

    has_more = length(quotes) == per_page

    socket
    |> assign(
      :pending_quotes,
      if(page == 1,
        do: quotes_with_votes,
        else: socket.assigns.pending_quotes ++ quotes_with_votes
      )
    )
    |> assign(:page, page)
    |> assign(:has_more, has_more)
  end

  defp load_author_votes_for_quotes(quotes) do
    Enum.map(quotes, fn quote ->
      if quote.author && quote.statements && quote.statements != [] do
        statement_ids = Enum.map(quote.statements, & &1.id)

        # Get author's votes for these statements
        votes =
          YouCongress.Votes.list_votes(
            author_ids: [quote.author.id],
            statement_ids: statement_ids,
            preload: []
          )

        # Create a map of statement_id -> vote for easy lookup
        votes_by_statement = Map.new(votes, fn vote -> {vote.statement_id, vote} end)

        # Add votes to each statement
        statements_with_votes =
          Enum.map(quote.statements, fn statement ->
            Map.put(statement, :author_vote, Map.get(votes_by_statement, statement.id))
          end)

        Map.put(quote, :statements, statements_with_votes)
      else
        quote
      end
    end)
  end

  defp update_quote_in_list(quotes, updated_quote) do
    # Reload the quote with all necessary preloads to get updated votes
    reloaded_quote = Opinions.get_opinion!(updated_quote.id, preload: [:author, :statements])
    quotes_with_votes = load_author_votes_for_quotes([reloaded_quote])
    updated_quote_with_votes = List.first(quotes_with_votes)

    Enum.map(quotes, fn quote ->
      if quote.id == updated_quote.id do
        updated_quote_with_votes
      else
        quote
      end
    end)
  end

  # Helper function to get styling classes based on vote response
  defp get_vote_style(response) do
    case response do
      :for -> "bg-green-700 text-white"
      :abstain -> "bg-blue-600 text-white"
      :against -> "bg-red-600 text-white"
      _ -> "bg-gray-100 text-gray-600"
    end
  end
end
