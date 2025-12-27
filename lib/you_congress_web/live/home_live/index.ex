defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Halls
  alias YouCongress.Opinions
  alias YouCongress.Track
  alias YouCongress.Votings
  alias YouCongressWeb.VotingLive.Index.Search
  alias YouCongressWeb.VotingLive.NewFormComponent

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
      |> assign(:votings, [])
      |> assign(:quotes, [])
      |> assign(:delegates, load_highlighted_delegates())
      |> assign(:selected_delegate_ids, [])
      |> assign(:selection_votings, [])
      |> assign(:user_votes, %{})
      |> assign(:auth_tab, :register)

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

  def handle_event("search-tab", %{"tab" => "motions"}, socket) do
    {:noreply, assign(socket, search_tab: :motions)}
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

  def handle_event("switch-auth-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, auth_tab: String.to_existing_atom(tab))}
  end

  def handle_event("toggle-delegate", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected_ids = socket.assigns.selected_delegate_ids

    new_selected_ids =
      if id in selected_ids do
        List.delete(selected_ids, id)
      else
        [id | selected_ids]
      end

    socket =
      socket
      |> assign(:selected_delegate_ids, new_selected_ids)
      |> assign_votings_for_selection(new_selected_ids)

    {:noreply, socket}
  end

  def handle_event(
        "vote",
        %{"id" => voting_id, "answer" => answer},
        %{assigns: %{current_user: nil}} = socket
      ) do
    voting_id = String.to_integer(voting_id)
    answer = String.to_existing_atom(answer)

    vote = %{answer: answer, voting_id: voting_id}
    new_user_votes = Map.put(socket.assigns.user_votes, voting_id, vote)

    socket =
      socket
      |> put_flash(:info, "Please sign up to save your vote.")
      |> assign(:user_votes, new_user_votes)

    {:noreply, socket}
  end

  def handle_event("vote", %{"id" => voting_id, "answer" => answer}, socket) do
    current_user = socket.assigns.current_user

    case YouCongress.Votes.create_or_update(%{
           voting_id: String.to_integer(voting_id),
           answer: answer,
           author_id: current_user.author_id,
           direct: true
         }) do
      {:ok, _vote} ->
        # Reload the voting to update the UI (could be optimized)
        selected_ids = socket.assigns.selected_delegate_ids

        {:noreply,
         assign_votings_for_selection(socket, selected_ids)
         |> put_flash(:info, "Voted #{String.capitalize(answer)}!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not cast vote.")}
    end
  end

  def handle_event("delete-vote", %{"id" => voting_id}, %{assigns: %{current_user: nil}} = socket) do
    voting_id = String.to_integer(voting_id)
    new_user_votes = Map.delete(socket.assigns.user_votes, voting_id)
    {:noreply, assign(socket, :user_votes, new_user_votes)}
  end

  def handle_event("delete-vote", %{"id" => voting_id}, socket) do
    current_user = socket.assigns.current_user
    voting_id = String.to_integer(voting_id)

    case YouCongress.Votes.delete_vote(%{
           voting_id: voting_id,
           author_id: current_user.author_id
         }) do
      {_count, _} ->
        # Reload to update UI
        selected_ids = socket.assigns.selected_delegate_ids

        {:noreply,
         assign_votings_for_selection(socket, selected_ids) |> put_flash(:info, "Vote removed.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not remove vote.")}
    end
  end

  @impl true
  def handle_info({NewFormComponent, {:put_flash, level, message}}, socket) do
    {:noreply, put_flash(socket, level, message)}
  end

  defp perform_search(socket, search) do
    Track.event("Search via Home", socket.assigns.current_user)
    votings = Votings.list_votings(title_contains: search, preload: [:halls])
    authors = Authors.list_authors(search: search)
    halls = Halls.list_halls(name_contains: search)
    quotes = Opinions.list_opinions(search: search, preload: [:author])

    search_tab =
      cond do
        Enum.any?(quotes) -> :quotes
        Enum.any?(authors) -> :delegates
        Enum.any?(votings) -> :motions
        Enum.any?(halls) -> :halls
        true -> :quotes
      end

    assign(socket,
      votings: votings,
      search: search,
      search_tab: search_tab,
      authors: authors,
      halls: halls,
      quotes: quotes
    )
  end

  defp load_highlighted_delegates do
    names = [
      "Stuart J. Russell",
      "Demis Hassabis",
      "Scott Alexander",
      "Yoshua Bengio",
      "Eliezer Yudkowsky",
      "Yann LeCun",
      "Geoffrey Hinton",
      "Gary Marcus",
      "Dario Amodei",
      "Sam Altman",
      "Elon Musk",
      "Max Tegmark"
    ]

    Authors.list_authors(names: names)
  end

  defp assign_votings_for_selection(socket, []) do
    assign(socket, :selection_votings, [])
  end

  defp assign_votings_for_selection(socket, selected_ids) do
    votings = Votings.list_votings_with_opinions_by_authors(selected_ids)

    user_votes =
      if current_user = socket.assigns.current_user do
        voting_ids = Enum.map(votings, & &1.id)

        YouCongress.Votes.list_votes(
          author_ids: [current_user.author_id],
          voting_ids: voting_ids
        )
        |> Map.new(&{&1.voting_id, &1})
      else
        %{}
      end

    socket
    |> assign(:selection_votings, votings)
    |> assign(:user_votes, user_votes)
  end

  def get_vote_answer(voting, author_id) do
    case Enum.find(voting.votes, &(&1.author_id == author_id)) do
      nil -> nil
      vote -> vote.answer
    end
  end

  def calculate_majority_vote(voting, selected_delegate_ids) do
    votes =
      voting.votes
      |> Enum.filter(&(&1.author_id in selected_delegate_ids))
      |> Enum.map(& &1.answer)

    if Enum.empty?(votes) do
      nil
    else
      counts = Enum.frequencies(votes)

      if Map.get(counts, :for, 0) == Map.get(counts, :against, 0) do
        :abstain
      else
        counts
        |> Enum.max_by(fn {_answer, count} -> count end)
        |> elem(0)
      end
    end
  end
end
