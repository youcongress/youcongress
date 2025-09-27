defmodule YouCongressWeb.QuoteReviewLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     socket
     |> assign(:page_title, "Review Quotes")
     |> assign(:pending_quotes, [])
     |> assign(:page, 1)
     |> assign(:per_page, 20)
     |> assign(:has_more, true)
     |> assign(:editing_quote_id, nil)
     |> assign(:edit_form, nil)}
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

    case Opinions.update_opinion(opinion, %{is_verified: true, verified_by_user_id: verifier_id}) do
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
    quote = Enum.find(socket.assigns.pending_quotes, &(&1.id == quote_id))

    if quote do
      # Create changeset with current quote data
      changeset = Opinion.changeset(quote, %{
        content: quote.content,
        year: quote.year,
        source_url: quote.source_url
      })
      form = to_form(changeset)

      {:noreply,
       socket
       |> assign(:editing_quote_id, quote_id)
       |> assign(:edit_form, form)}
    else
      {:noreply, put_flash(socket, :error, "Quote not found")}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_quote_id, nil)
     |> assign(:edit_form, nil)}
  end

  def handle_event("validate_edit", params, socket) do
    # Extract opinion params, filtering out vote-related params
    opinion_params =
      params
      |> Map.drop(["quote_id"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "vote_") end)
      |> Map.new()

    # Get the current quote being edited
    quote_id = socket.assigns.editing_quote_id
    quote = Enum.find(socket.assigns.pending_quotes, &(&1.id == quote_id))

    changeset =
      (quote || %Opinion{})
      |> Opinion.changeset(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :edit_form, to_form(changeset))}
  end

  def handle_event("save_edit", params, socket) do
    quote_id = String.to_integer(params["quote_id"])

    # Extract opinion params, filtering out vote-related params
    opinion_params =
      params
      |> Map.drop(["quote_id"])
      |> Enum.reject(fn {key, _value} -> String.starts_with?(key, "vote_") end)
      |> Map.new()

    quote = Opinions.get_opinion!(quote_id, preload: [:author, :votings])

    case Opinions.update_opinion(quote, opinion_params) do
      {:ok, updated_quote} ->
        # Update votes if they were changed
        update_author_votes(params, quote, socket)

        # Update the quote in the list
        updated_quotes = update_quote_in_list(socket.assigns.pending_quotes, updated_quote)

        {:noreply,
         socket
         |> assign(:pending_quotes, updated_quotes)
         |> assign(:editing_quote_id, nil)
         |> assign(:edit_form, nil)
         |> put_flash(:info, "Quote updated successfully")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:edit_form, to_form(changeset))
         |> put_flash(:error, "Failed to update quote")}
    end
  end

  defp remove_from_list(socket, id) do
    list = Enum.reject(socket.assigns.pending_quotes, &(&1.id == id))
    assign(socket, :pending_quotes, list)
  end

  defp load_pending_quotes(socket, page) do
    %{assigns: %{per_page: per_page}} = socket
    offset = (page - 1) * per_page

    quotes =
      Opinions.list_opinions(
        only_quotes: true,
        is_verified: false,
        order_by: [desc: :inserted_at],
        limit: per_page,
        offset: offset,
        preload: [:author, :votings]
      )

    # Load author votes for each quote's votings
    quotes_with_votes = load_author_votes_for_quotes(quotes)

    has_more = length(quotes) == per_page

    socket
    |> assign(:pending_quotes, if(page == 1, do: quotes_with_votes, else: socket.assigns.pending_quotes ++ quotes_with_votes))
    |> assign(:page, page)
    |> assign(:has_more, has_more)
  end

  defp load_author_votes_for_quotes(quotes) do
    Enum.map(quotes, fn quote ->
      if quote.author && quote.votings && quote.votings != [] do
        voting_ids = Enum.map(quote.votings, & &1.id)

        # Get author's votes for these votings
        votes = YouCongress.Votes.list_votes(
          author_ids: [quote.author.id],
          voting_ids: voting_ids,
          preload: [:answer]
        )

        # Create a map of voting_id -> vote for easy lookup
        votes_by_voting = Map.new(votes, fn vote -> {vote.voting_id, vote} end)

        # Add votes to each voting
        votings_with_votes = Enum.map(quote.votings, fn voting ->
          Map.put(voting, :author_vote, Map.get(votes_by_voting, voting.id))
        end)

        Map.put(quote, :votings, votings_with_votes)
      else
        quote
      end
    end)
  end

  defp update_author_votes(params, quote, _socket) do
    if quote.author do
      # Process vote updates for each voting
      Enum.each(quote.votings, fn voting ->
        vote_param_key = "vote_#{voting.id}"

        if Map.has_key?(params, vote_param_key) do
          response = params[vote_param_key]

          if response != "" do
            # Create or update the vote
            answer_id = Answers.get_answer_id(response)

            Votes.create_or_update(%{
              voting_id: voting.id,
              author_id: quote.author.id,
              answer_id: answer_id,
              direct: true
            })
          else
            # Delete the vote if "No position" is selected
            case Votes.get_by(voting_id: voting.id, author_id: quote.author.id) do
              nil -> :ok
              vote -> Votes.delete_vote(vote)
            end
          end
        end
      end)
    end
  end

  defp update_quote_in_list(quotes, updated_quote) do
    # Reload the quote with all necessary preloads to get updated votes
    reloaded_quote = Opinions.get_opinion!(updated_quote.id, preload: [:author, :votings])
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
      "Strongly agree" -> "bg-green-700 text-white"
      "Agree" -> "bg-green-600 text-white"
      "Abstain" -> "bg-blue-600 text-white"
      "N/A" -> "bg-gray-600 text-white"
      "Disagree" -> "bg-orange-600 text-white"
      "Strongly disagree" -> "bg-red-600 text-white"
      _ -> "bg-gray-100 text-gray-600"
    end
  end
end
