defmodule YouCongressWeb.AuthorLive.Show do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias YouCongress.DigitalTwins.Regenerate
  alias Phoenix.LiveView.Socket
  alias YouCongress.Votes
  alias YouCongress.Likes
  alias YouCongress.Track
  alias YouCongressWeb.AuthorLive.FormComponent
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.VotingLive.CastVoteComponent
  alias YouCongressWeb.Components.SwitchComponent

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign(:order_by_date, false)

    if connected?(socket) do
      Track.event("View Author", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    order_by_date = socket.assigns.order_by_date

    author = get_author!(params)

    votes = load_votes(author.id, order_by_date)

    name = author.name || author.twitter_username || "Anonymous user"
    title = page_title(socket.assigns.live_action, name)

    current_user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:page_title, title)
     |> assign(:page_description, "Delegate to #{name} to vote on your behalf.")
     |> assign(:author, author)
     |> assign(:votes, votes)
     |> assign(:regenerating_opinion_id, nil)
     |> assign(
       :current_user_votes_by_voting_id,
       get_current_user_votes_by_voting_id(current_user)
     )
     |> assign_delegating?()
     |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))}
  end

  def get_current_user_votes_by_voting_id(nil), do: %{}

  def get_current_user_votes_by_voting_id(current_user) do
    [author_ids: [current_user.author_id], preload: [:answer]]
    |> Votes.list_votes()
    |> Enum.reduce(%{}, fn vote, acc -> Map.put(acc, vote.voting_id, vote) end)
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
        send(self(), :update_current_user_votes_by_voting_id)

        {:noreply, assign(socket, :delegating?, false)}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  def handle_event("toggle-delegate", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :warning, "Log in to unlock delegate voting.")}
  end

  def handle_event("toggle-delegate", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        Track.event("Delegate", current_user)
        send(self(), :update_current_user_votes_by_voting_id)

        {:noreply, assign(socket, :delegating?, true)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def handle_event("regenerate", %{"opinion_id" => opinion_id}, socket) do
    opinion_id = String.to_integer(opinion_id)
    send(self(), {:regenerate, opinion_id})
    {:noreply, assign(socket, :regenerating_opinion_id, opinion_id)}
  end

  def handle_event("toggle-order-by-date", _, socket) do
    %{assigns: %{order_by_date: order_by_date, author: author}} = socket
    order_by_date = !order_by_date

    socket =
      socket
      |> assign(:order_by_date, order_by_date)
      |> assign(:votes, load_votes(author.id, order_by_date))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:regenerate, opinion_id}, socket) do
    %{assigns: %{current_user: current_user, votes: votes}} = socket

    case Regenerate.regenerate(opinion_id, current_user) do
      {:ok, {_, vote}} ->
        vote = Votes.get_vote(vote.id, preload: [:voting, :answer, :opinion])
        votes = Enum.map(votes, fn v -> if v.id == vote.id, do: vote, else: v end)

        socket =
          socket
          |> assign(:votes, votes)
          |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
          |> assign(:regenerating_opinion_id, nil)
          |> put_flash(:info, "Opinion regenerated.")

        {:noreply, socket}

      error ->
        Logger.debug("Error regenerating opinion. #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error regenerating opinion.")}
    end
  end

  def handle_info(:update_current_user_votes_by_voting_id, socket) do
    current_user = socket.assigns.current_user

    socket =
      assign(
        socket,
        :current_user_votes_by_voting_id,
        get_current_user_votes_by_voting_id(current_user)
      )

    {:noreply, socket}
  end

  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def author_path(%{twitter_username: nil, id: author_id}) do
    ~p"/a/#{author_id}"
  end

  def author_path(%{twitter_username: twitter_username}) do
    ~p"/x/#{twitter_username}"
  end

  defp page_title(:show, name), do: name
  defp page_title(:edit, name), do: "Edit Author #{name}"

  defp assign_delegating?(%{assigns: %{current_user: nil}} = socket) do
    assign(socket, :delegating?, false)
  end

  @spec assign_delegating?(Socket.t()) :: Socket.t()
  defp assign_delegating?(%{assigns: %{author: author, current_user: current_user}} = socket) do
    delegating = Delegations.delegating?(current_user.author_id, author.id)
    assign(socket, :delegating?, delegating)
  end

  defp load_votes(author_id, false) do
    Votes.list_votes(
      author_ids: [author_id],
      order_by_strong_opinions_first: true,
      preload: [:voting, :answer, :opinion]
    )
  end

  defp load_votes(author_id, true) do
    Votes.list_votes(
      author_ids: [author_id],
      order_by: [desc: :id],
      preload: [:voting, :answer, :opinion]
    )
  end
end
