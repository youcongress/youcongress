defmodule YouCongressWeb.AuthorLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias Phoenix.LiveView.Socket
  alias YouCongress.Votes
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.AuthorLive.FormComponent
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.Tools.Tooltip

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Author", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    author = get_author!(params)
    votes = Votes.list_votes_by_author_id(author.id, preload: [:voting, :answer, :opinion])
    title = page_title(socket.assigns.live_action)

    {:noreply,
     socket
     |> assign(page_title: title, author: author, votes: votes)
     |> assign_delegating?()}
  end

  defp get_author!(%{"id" => user_id}) do
    Authors.get_author!(user_id)
  end

  defp get_author!(%{"twitter_username" => twitter_username}) do
    Authors.get_author_by_twitter_username!(twitter_username)
  end

  @impl true
  def handle_event(
        "toggle-delegate",
        %{"author_id" => author_id},
        %{assigns: %{delegating?: true}} = socket
      ) do
    %{assigns: %{current_user: current_user}} = socket

    deleguee_id = current_user.author_id
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
      {:ok, _} ->
        Track.event("Remove Delegate", current_user)

        socket =
          socket
          |> assign(:delegating?, false)
          |> put_flash(:info, "Delegation deleted successfully.")
          |> assign_counters()

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  def handle_event("toggle-delegate", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to delegate.")}
  end

  def handle_event("toggle-delegate", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, true)
          |> put_flash(:info, "Delegation created successfully.")
          |> assign_counters()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def author_path(%{twitter_username: nil, id: author_id}) do
    ~p"/a/#{author_id}"
  end

  def author_path(%{twitter_username: twitter_username}) do
    ~p"/x/#{twitter_username}"
  end

  defp page_title(:show), do: "Show Author"
  defp page_title(:edit), do: "Edit Author"

  defp assign_delegating?(%{assigns: %{current_user: nil}} = socket) do
    assign(socket, :delegating?, false)
  end

  @spec assign_delegating?(Socket.t()) :: Socket.t()
  defp assign_delegating?(%{assigns: %{author: author, current_user: current_user}} = socket) do
    delegating = Delegations.delegating?(current_user.author_id, author.id)
    assign(socket, :delegating?, delegating)
  end
end
