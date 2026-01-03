defmodule YouCongressWeb.OpinionLive.Show do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Likes
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Track
  alias YouCongress.Delegations
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Statements
  alias YouCongress.Votes
  alias YouCongress.Accounts.Permissions

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
       selected_statement_id: nil,
       selected_statement_title: nil,
       editing_opinion_id: nil
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
      "verified_at" => DateTime.utc_now(),
      "ancestry" => ancestry
    }

    case Opinions.create_opinion(opinion_params) do
      {:ok, %{opinion: opinion}} ->
        Track.event("New Opinion", current_user)

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

  def handle_event("edit", %{"opinion_id" => opinion_id}, socket) do
    opinion_id = String.to_integer(opinion_id)
    {:noreply, assign(socket, :editing_opinion_id, opinion_id)}
  end

  def handle_event("delete-comment", %{"opinion_id" => opinion_id}, socket) do
    opinion = Opinions.get_opinion!(opinion_id, preload: [:statements])

    {_count, nil} =
      Opinions.delete_opinion_and_descendants(opinion)

    Track.event("Delete Opinion", socket.assigns.current_user)

    parent_opinion_id = Opinion.parent_id(opinion)
    url = if parent_opinion_id, do: "/c/#{parent_opinion_id}", else: "/home"

    socket =
      socket
      |> redirect(to: url)
      |> put_flash(:info, "Opinion deleted successfully.")

    {:noreply, socket}
  end

  def handle_event("toggle-search", _params, socket) do
    {:noreply, assign(socket, :show_search, !socket.assigns.show_search)}
  end

  def handle_event("search-statements", %{"value" => query}, socket) do
    %{assigns: %{opinion: opinion}} = socket

    search_results =
      if String.length(query) >= 2 do
        # Get existing statement IDs for this opinion
        existing_statement_ids = Enum.map(opinion.statements, & &1.id)

        # Search for statements and exclude ones already associated
        Statements.list_statements(title_contains: query, limit: 10)
        |> Enum.reject(fn statement -> statement.id in existing_statement_ids end)
      else
        []
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, search_results)}
  end

  def handle_event("show-vote-options", %{"statement_id" => statement_id}, socket) do
    %{assigns: %{search_results: search_results}} = socket

    statement_id_int = String.to_integer(statement_id)
    statement = Enum.find(search_results, fn s -> s.id == statement_id_int end)

    socket =
      socket
      |> assign(:show_search, false)
      |> assign(:show_vote_modal, true)
      |> assign(:selected_statement_id, statement_id_int)
      |> assign(:selected_statement_title, statement.title)

    {:noreply, socket}
  end

  def handle_event("cancel-vote-modal", _params, socket) do
    socket =
      socket
      |> assign(:show_vote_modal, false)
      |> assign(:selected_statement_id, nil)
      |> assign(:selected_statement_title, nil)

    {:noreply, socket}
  end

  def handle_event(
        "add-to-statement-with-vote",
        %{"statement_id" => statement_id, "answer" => answer},
        socket
      ) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    opinion = Map.put(opinion, :user_id, current_user.id)

    with {:ok, _updated_opinion} <-
           Opinions.add_opinion_to_statement(opinion, String.to_integer(statement_id)),
         {:ok, _vote} <-
           create_or_update_vote(current_user, opinion, String.to_integer(statement_id), answer) do
      Track.event("Add Opinion to Statement with Vote", current_user)

      socket =
        socket
        |> load_opinion!(opinion.id)
        |> assign(:show_search, false)
        |> assign(:search_query, "")
        |> assign(:search_results, [])
        |> assign(:show_vote_modal, false)
        |> assign(:selected_statement_id, nil)
        |> assign(:selected_statement_title, nil)
        |> put_flash(:info, "Opinion added to statement with your vote (#{answer}) successfully.")

      {:noreply, socket}
    else
      {:error, :already_associated} ->
        {:noreply,
         socket |> put_flash(:error, "Opinion is already associated with this statement.")}

      {:error, error} ->
        Logger.error("Error adding opinion to statement: #{inspect(error)}")
        {:noreply, socket |> put_flash(:error, "Failed to add opinion to statement.")}
    end
  end

  def handle_event("add-to-statement", %{"statement_id" => statement_id}, socket) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    opinion = Map.put(opinion, :user_id, current_user.id)

    case Opinions.add_opinion_to_statement(opinion, String.to_integer(statement_id)) do
      {:ok, _updated_opinion} ->
        Track.event("Add Opinion to Statement", current_user)

        socket =
          socket
          |> load_opinion!(opinion.id)
          |> assign(:show_search, false)
          |> assign(:search_query, "")
          |> assign(:search_results, [])
          |> put_flash(:info, "Opinion added to statement successfully.")

        {:noreply, socket}

      {:error, :already_associated} ->
        {:noreply,
         socket |> put_flash(:error, "Opinion is already associated with this statement.")}

      {:error, error} ->
        Logger.error("Error adding opinion to statement: #{inspect(error)}")
        {:noreply, socket |> put_flash(:error, "Failed to add opinion to statement.")}
    end
  end

  @impl true
  def handle_info({:opinion_updated, updated_opinion}, socket) do
    socket =
      socket
      |> load_opinion!(updated_opinion.id)
      |> load_delegations()
      |> assign(:editing_opinion_id, nil)
      |> put_flash(:info, "Opinion updated successfully")

    {:noreply, socket}
  end

  def handle_info({:opinion_update_error, _changeset}, socket) do
    {:noreply, put_flash(socket, :error, "Failed to update opinion")}
  end

  def handle_info(:opinion_edit_cancelled, socket) do
    {:noreply, assign(socket, :editing_opinion_id, nil)}
  end

  defp create_or_update_vote(_current_user, opinion, statement_id, answer) do
    alias YouCongress.Votes

    answer_atom = String.downcase(answer) |> String.to_existing_atom()

    vote_params = %{
      author_id: opinion.author_id,
      statement_id: statement_id,
      answer: answer_atom,
      opinion_id: opinion.id,
      direct: true,
      twin: false
    }

    Votes.create_or_update(vote_params)
  end

  defp load_opinion!(socket, opinion_id) do
    opinion = Opinions.get_opinion!(opinion_id, preload: [:author, :statements])
    opinion_with_votes = load_author_votes_for_opinion(opinion)
    assign(socket, opinion: opinion_with_votes)
  end

  defp load_author_votes_for_opinion(opinion) do
    if opinion.author && opinion.statements && opinion.statements != [] do
      statement_ids = Enum.map(opinion.statements, & &1.id)

      # Get author's votes for these statements
      votes =
        YouCongress.Votes.list_votes(
          author_ids: [opinion.author.id],
          statement_ids: statement_ids,
          preload: []
        )

      # Create a map of statement_id -> vote for easy lookup
      votes_by_statement = Map.new(votes, fn vote -> {vote.statement_id, vote} end)

      # Add votes to each statement
      statements_with_votes =
        Enum.map(opinion.statements, fn statement ->
          Map.put(statement, :author_vote, Map.get(votes_by_statement, statement.id))
        end)

      Map.put(opinion, :statements, statements_with_votes)
    else
      opinion
    end
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

  defp quote?(%Opinion{} = opinion) do
    !is_nil(opinion.source_url) && !opinion.twin && is_nil(opinion.ancestry)
  end

  defp quote?(_), do: false
end
