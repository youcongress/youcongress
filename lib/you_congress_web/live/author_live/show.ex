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

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    if connected?(socket) do
      Track.event("View Author", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    author = get_author!(params)
    votes = Votes.list_votes_by_author_id(author.id, preload: [:voting, :answer, :opinion])

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

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :warning, "Log in to like.")}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        liked_opinion_ids: liked_opinion_ids
      }
    } = socket

    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:liked_opinion_ids, [opinion_id | liked_opinion_ids])
          |> update_likes_count(opinion_id, &(&1 + 1))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to like opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        liked_opinion_ids: liked_opinion_ids
      }
    } = socket

    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:liked_opinion_ids, Enum.filter(liked_opinion_ids, &(&1 != opinion_id)))
          |> update_likes_count(opinion_id, &(&1 - 1))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to unlike opinion.")}
    end
  end

  def handle_event("regenerate", %{"opinion_id" => opinion_id}, socket) do
    opinion_id = String.to_integer(opinion_id)
    send(self(), {:regenerate, opinion_id})
    {:noreply, assign(socket, :regenerating_opinion_id, opinion_id)}
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

  defp update_likes_count(socket, opinion_id, operation) do
    %{assigns: %{votes: votes}} = socket
    assign(socket, :votes, Enum.map(votes, &replace_opinion_in_vote(&1, opinion_id, operation)))
  end

  defp replace_opinion_in_vote(%{opinion_id: opinion_id} = vote, opinion_id, operation) do
    opinion = Map.put(vote.opinion, :likes_count, operation.(vote.opinion.likes_count))
    Map.put(vote, :opinion, opinion)
  end

  defp replace_opinion_in_vote(vote, _, _), do: vote
end
