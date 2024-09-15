defmodule YouCongressWeb.AuthorLive.Show do
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias Phoenix.LiveView.Socket
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers
  alias YouCongress.Likes
  alias YouCongress.Track
  alias YouCongressWeb.AuthorLive.FormComponent
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.VotingLive.Show.CastComponent
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongress.DelegationVotes

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

    name = author.name || author.twitter_username || "Anonymous user"
    title = page_title(socket.assigns.live_action, name)

    current_user = socket.assigns.current_user

    {:noreply,
     socket
     |> assign(:page_title, title)
     |> assign(:page_description, "Delegate to #{name} to vote on your behalf.")
     |> assign(:author, author)
     |> assign(:votes, votes)
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
    %{assigns: %{current_user: current_user, author: author}} = socket

    deleguee_id = current_user.author_id
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
      {:ok, _} ->
        Track.event("Remove Delegate", current_user)

        socket =
          socket
          |> assign(:delegating?, false)
          |> assign(
            :current_user_votes_by_voting_id,
            get_current_user_votes_by_voting_id(current_user)
          )
          |> assign_counters()
          |> put_flash(:info, "You're no longer voting as #{author.name}.")

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  def handle_event("toggle-delegate", _, %{assigns: %{current_user: nil}} = socket) do
    author = socket.assigns.author

    msg =
      "You must be logged in to delegate (and automatically vote as #{author.name} – unless you vote directly)."

    {:noreply, put_flash(socket, :error, msg)}
  end

  def handle_event("toggle-delegate", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user, author: author}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, true)
          |> assign(
            :current_user_votes_by_voting_id,
            get_current_user_votes_by_voting_id(current_user)
          )
          |> assign_counters()
          |> put_flash(:info, "You're now voting as #{author.name}.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to like.")}
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

  def handle_event("vote", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to vote.")}
  end

  def handle_event("vote", %{"response" => response, "voting_id" => voting_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        current_user_votes_by_voting_id: current_user_votes_by_voting_id,
        author: author
      }
    } = socket

    voting_id = String.to_integer(voting_id)
    answer_id = Answers.get_basic_answer_id(response)

    case Votes.create_or_update(%{
           voting_id: voting_id,
           answer_id: answer_id,
           author_id: current_user.author_id,
           direct: true
         }) do
      {:ok, vote} ->
        Track.event("Vote", current_user)

        vote = Votes.get_vote([id: vote.id], preload: [:answer])

        current_user_votes_by_voting_id =
          Map.put(current_user_votes_by_voting_id, voting_id, vote)

        socket =
          socket
          |> assign(:current_user_votes_by_voting_id, current_user_votes_by_voting_id)
          |> maybe_replace_vote_in_votes(
            current_user && author.id == current_user.author_id,
            vote.id,
            vote.id
          )
          |> put_flash(:info, "You voted #{vote.answer.response}")

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
  end

  def handle_event("delete-direct-vote", %{"voting_id" => voting_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        current_user_votes_by_voting_id: current_user_votes_by_voting_id,
        author: author
      }
    } = socket

    voting_id = String.to_integer(voting_id)
    current_user_vote = current_user_votes_by_voting_id[voting_id]

    case Votes.delete_vote(current_user_vote) do
      {:ok, deleted_vote} ->
        Track.event("Delete Vote", current_user)

        DelegationVotes.update_author_voting_delegated_votes(current_user.author_id, voting_id)

        vote =
          Votes.get_vote([voting_id: voting_id, author_id: current_user.author_id],
            preload: [:answer]
          )

        delegating_txt = vote && " You're delegating now."
        same_user? = current_user && author.id == current_user.author_id

        socket =
          socket
          |> assign(
            :current_user_votes_by_voting_id,
            Map.put(current_user_votes_by_voting_id, voting_id, vote)
          )
          |> maybe_replace_vote_in_votes(same_user?, deleted_vote.id, vote.id)
          |> put_flash(:info, "Direct vote deleted.#{delegating_txt}")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting vote.")}
    end
  end

  defp maybe_replace_vote_in_votes(socket, false, _, _), do: socket

  defp maybe_replace_vote_in_votes(socket, true, old_vote_id, new_vote_id) do
    vote = Votes.get_vote([id: new_vote_id], preload: [:answer, :opinion, :voting])

    votes =
      Enum.map(socket.assigns.votes, fn v ->
        if v.id == old_vote_id do
          vote
        else
          v
        end
      end)

    assign(socket, :votes, votes)
  end

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
