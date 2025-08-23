defmodule YouCongressWeb.OpinionLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Likes
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Track
  alias YouCongress.Delegations
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Votings

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    %{assigns: %{current_user: current_user}} = socket

    socket = assign(socket, :liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))

    if connected?(socket) do
      Track.event("View Opinion", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => opinion_id}, _, socket) do
    socket = load_opinion!(socket, opinion_id)
    %{assigns: %{opinion: opinion}} = socket
    parent_opinion = Opinion.parent(opinion)
    changeset = Opinions.change_opinion(%Opinions.Opinion{})

    socket = load_delegations(socket)

    {:noreply,
     socket
     |> assign(
       page_title: "Opinion",
       opinion: opinion,
       parent_opinion: parent_opinion,
       changeset: changeset,
       search_query: "",
       search_results: [],
       show_search: false,
       show_vote_modal: false,
       selected_voting_id: nil,
       selected_voting_title: nil
     )}
  end

  @impl true
  def handle_event("validate", %{"opinion" => opinion_params}, socket) do
    changeset =
      %Opinions.Opinion{}
      |> Opinions.change_opinion(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"opinion" => %{"content" => content}}, socket) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    ancestry =
      if opinion.ancestry, do: "#{opinion.ancestry}/#{opinion.id}", else: "#{opinion.id}"

    opinion_params = %{
      "content" => content,
      "author_id" => current_user.author_id,
      "user_id" => current_user.id,
      "ancestry" => ancestry
    }

    case Opinions.create_opinion(opinion_params) do
      {:ok, opinion} ->
        Track.event("New Opinion", current_user)

        # We do this synchronous as we want the reply be ready when we redirect
        YouCongress.Opinions.maybe_reply_by_ai(opinion)

        {:noreply,
         socket
         |> put_flash(:info, "Opinion created successfully.")
         |> redirect(to: "/c/#{opinion.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def handle_event("remove-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    case Delegations.delete_delegation(current_user, author_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_opinion!(opinion.id)
          |> load_delegations()
          |> put_flash(:info, "Delegation removed successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to remove delegation.")}
    end
  end

  def handle_event("add-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    case Delegations.create_delegation(current_user, author_id) do
      {:ok, _} ->
        socket =
          socket
          |> load_opinion!(opinion.id)
          |> load_delegations()
          |> put_flash(:info, "Delegated successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to delegate.")}
    end
  end

  def handle_event("delete-comment", %{"opinion_id" => opinion_id}, socket) do
    opinion = Opinions.get_opinion!(opinion_id, preload: [:votings])
    opinion_id = opinion.id

    {_count, nil} =
      Opinions.delete_opinion_and_descendants(opinion)

    Track.event("Delete Opinion", socket.assigns.current_user)

    socket =
      socket
      |> redirect_or_load_variables(opinion)
      |> put_flash(:info, "Opinion deleted successfully.")

    {:noreply, socket}
  end

  def handle_event("toggle-search", _params, socket) do
    {:noreply, assign(socket, :show_search, !socket.assigns.show_search)}
  end

  def handle_event("search-votings", %{"value" => query}, socket) do
    %{assigns: %{opinion: opinion}} = socket

    search_results =
      if String.length(query) >= 2 do
        # Get existing voting IDs for this opinion
        existing_voting_ids = Enum.map(opinion.votings, & &1.id)

        # Search for votings and exclude ones already associated
        Votings.list_votings(title_contains: query, limit: 10)
        |> Enum.reject(fn voting -> voting.id in existing_voting_ids end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, search_results)}
  end

  def handle_event("show-vote-options", %{"voting_id" => voting_id}, socket) do
    %{assigns: %{search_results: search_results}} = socket

    voting_id_int = String.to_integer(voting_id)
    voting = Enum.find(search_results, fn v -> v.id == voting_id_int end)

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:show_vote_modal, true)
      |> assign(:selected_voting_id, voting_id_int)
      |> assign(:selected_voting_title, voting.title)

    {:noreply, socket}
  end

  def handle_event("cancel-vote-modal", _params, socket) do
    socket =
      socket
      |> assign(:show_vote_modal, false)
      |> assign(:selected_voting_id, nil)
      |> assign(:selected_voting_title, nil)

    {:noreply, socket}
  end

  def handle_event(
        "add-to-voting-with-vote",
        %{"voting_id" => voting_id, "answer" => answer},
        socket
      ) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    with {:ok, _updated_opinion} <-
           Opinions.add_opinion_to_voting(opinion, String.to_integer(voting_id)),
         {:ok, _vote} <-
           create_or_update_vote(current_user, opinion, String.to_integer(voting_id), answer) do
      Track.event("Add Opinion to Voting with Vote", current_user)

      socket =
        socket
        |> load_opinion!(opinion.id)
        |> assign(:show_search, false)
        |> assign(:search_query, "")
        |> assign(:search_results, [])
        |> assign(:show_vote_modal, false)
        |> assign(:selected_voting_id, nil)
        |> assign(:selected_voting_title, nil)
        |> put_flash(:info, "Opinion added to voting with your vote (#{answer}) successfully.")

      {:noreply, socket}
    else
      {:error, :already_associated} ->
        {:noreply, socket |> put_flash(:error, "Opinion is already associated with this voting.")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to add opinion to voting.")}
    end
  end

  def handle_event("add-to-voting", %{"voting_id" => voting_id}, socket) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    case Opinions.add_opinion_to_voting(opinion, String.to_integer(voting_id)) do
      {:ok, _updated_opinion} ->
        Track.event("Add Opinion to Voting", current_user)

        socket =
          socket
          |> load_opinion!(opinion.id)
          |> assign(:show_search, false)
          |> assign(:search_query, "")
          |> assign(:search_results, [])
          |> put_flash(:info, "Opinion added to voting successfully.")

        {:noreply, socket}

      {:error, :already_associated} ->
        {:noreply, socket |> put_flash(:error, "Opinion is already associated with this voting.")}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to add opinion to voting.")}
    end
  end

  defp create_or_update_vote(current_user, opinion, voting_id, answer) do
    alias YouCongress.Votes
    alias YouCongress.Votes.Answers

    answer_id = Answers.answer_id_by_response(answer)

    vote_params = %{
      author_id: current_user.author_id,
      voting_id: voting_id,
      answer_id: answer_id,
      opinion_id: opinion.id,
      direct: true,
      twin: false
    }

    Votes.create_or_update(vote_params)
  end

  defp redirect_or_load_variables(socket, opinion) do
    parent_opinion_id = Opinion.parent_id(opinion)

    if parent_opinion_id do
      socket
      |> load_opinion!(parent_opinion_id)
      |> load_delegations()
    else
      redirect(socket, to: "/home")
    end
  end

  defp load_opinion!(socket, opinion_id) do
    opinion = Opinions.get_opinion!(opinion_id, preload: [:author, :votings])
    assign(socket, opinion: opinion)
  end

  defp load_delegations(socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    child_opinions =
      Opinions.list_opinions(
        ancestry: Opinion.path_str(opinion),
        preload: [:author],
        order_by: [desc: :id]
      )

    delegating = get_delegating(current_user, opinion.author_id)
    delegate_ids = get_delegate_ids(current_user)

    child_opinions_delegations =
      child_opinions
      |> Enum.map(& &1.author_id)
      |> Enum.uniq()
      |> Enum.into(%{}, fn author_id ->
        {author_id, author_id in delegate_ids}
      end)

    assign(socket,
      delegating: delegating,
      child_opinions_delegations: child_opinions_delegations,
      child_opinions: child_opinions
    )
  end

  defp get_delegating(nil, _), do: false

  defp get_delegating(%{author_id: current_user_author_id}, opinion_author_id) do
    Delegations.delegating?(current_user_author_id, opinion_author_id)
  end

  defp get_delegate_ids(nil), do: []

  defp get_delegate_ids(%{author_id: author_id}) do
    Delegations.list_delegation_ids(deleguee_id: author_id)
  end
end
