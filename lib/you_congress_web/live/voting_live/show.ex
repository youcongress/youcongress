defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Likes
  alias YouCongress.Delegations
  alias YouCongress.Votings
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers
  alias YouCongress.DelegationVotes
  alias YouCongressWeb.VotingLive.Show.VotesLoader
  alias YouCongressWeb.VotingLive.Show.CurrentUserVoteComponent
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.VotingLive.Show.Comments
  alias YouCongress.Track
  alias YouCongress.Workers.PublicFiguresWorker
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.VotingLive.Show.CastComponent

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      Track.event("View Voting", current_user)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug}, _, socket) do
    voting = Votings.get_voting_by_slug!(slug)
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, page_title(socket.assigns.live_action, voting.title))
      |> assign(
        :page_description,
        "Find agreement, understand disagreement."
      )
      |> assign(reload: false)
      |> VotesLoader.load_voting_and_votes(voting.id)
      |> load_random_votings(voting.id)
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user, voting))

    current_user_vote = socket.assigns.current_user_vote
    socket = assign(socket, editing: !current_user_vote || !current_user_vote.opinion_id)

    if socket.assigns.voting.generating_left > 0 do
      Process.send_after(self(), :reload, 1_000)
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate-votes", %{"voting_id" => voting_id}, socket) do
    voting_id = String.to_integer(voting_id)

    %{voting_id: voting_id}
    |> PublicFiguresWorker.new()
    |> Oban.insert()

    Track.event("Generate AI opinions", socket.assigns.current_user)

    Process.send_after(self(), :reload, 1_000)

    {:noreply, clear_flash(socket)}
  end

  def handle_event("vote", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to vote.")}
  end

  def handle_event("vote", %{"response" => response}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        voting: voting
      }
    } = socket

    answer_id = Answers.get_basic_answer_id(response)

    case Votes.create_or_update(%{
           voting_id: voting.id,
           answer_id: answer_id,
           author_id: current_user.author_id,
           direct: true
         }) do
      {:ok, _} ->
        Track.event("Vote", current_user)

        socket =
          socket
          |> VotesLoader.load_voting_and_votes(socket.assigns.voting.id)
          |> put_flash(
            :info,
            "You voted #{response}."
          )

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
  end

  def handle_event("delete-direct-vote", _, socket) do
    %{
      assigns: %{current_user_vote: current_user_vote, current_user: current_user, voting: voting}
    } = socket

    case Votes.delete_vote(current_user_vote) do
      {:ok, _} ->
        Track.event("Delete Vote", current_user)

        DelegationVotes.update_author_voting_delegated_votes(current_user.author_id, voting.id)

        socket =
          socket
          |> VotesLoader.load_voting_and_votes(voting.id)
          |> put_flash(:info, "Direct vote deleted.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting vote.")}
    end
  end

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to like.")}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, liked_opinion_ids: liked_opinion_ids}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> replace_opinion(opinion_id, &(&1 + 1))
          |> assign(:liked_opinion_ids, [opinion_id | liked_opinion_ids])

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error liking opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, liked_opinion_ids: liked_opinion_ids}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> replace_opinion(opinion_id, &(&1 - 1))
          |> assign(:liked_opinion_ids, Enum.filter(liked_opinion_ids, &(&1 != opinion_id)))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error unliking opinion.")}
    end
  end

  def handle_event("post", %{"comment" => opinion}, socket) do
    Comments.post_event(opinion, socket)
  end

  def handle_event("cancel-edit", _, socket) do
    socket =
      socket
      |> assign(editing: false)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event("delete-comment", _, socket) do
    Comments.delete_event(socket)
  end

  def handle_event("reload", _, socket) do
    socket =
      socket
      |> VotesLoader.load_voting_and_votes(socket.assigns.voting.id)
      |> assign(reload: false)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to delegate.")}
  end

  def handle_event("add-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, true)
          |> put_flash(
            :info,
            "Added to your delegation list. You're voting as the majority of your delegates – unless you directly vote."
          )
          |> VotesLoader.assign_main_variables(
            voting,
            current_user
          )
          |> assign(reload: true)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def handle_event("edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("remove-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, false)
          |> put_flash(:info, "Removed from your delegation list.")
          |> VotesLoader.assign_main_variables(
            voting,
            current_user
          )
          |> assign(reload: true)

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  @impl true
  def handle_info(:reload, socket) do
    socket = VotesLoader.load_voting_and_votes(socket, socket.assigns.voting.id)

    if socket.assigns.voting.generating_left > 0 do
      Process.send_after(self(), :reload, 1_000)
    end

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp replace_opinion(socket, opinion_id, operation) do
    %{
      assigns: %{
        votes_from_delegates: votes_from_delegates,
        votes_from_non_delegates: votes_from_non_delegates,
        current_user_vote: current_user_vote
      }
    } = socket

    socket
    |> assign(
      :votes_from_delegates,
      Enum.map(votes_from_delegates, &replace_opinion_in_vote(&1, opinion_id, operation))
    )
    |> assign(
      :votes_from_non_delegates,
      Enum.map(votes_from_non_delegates, &replace_opinion_in_vote(&1, opinion_id, operation))
    )
    |> assign(
      :current_user_vote,
      replace_opinion_in_vote(current_user_vote, opinion_id, operation)
    )
  end

  defp replace_opinion_in_vote(
         %{opinion: %{id: opinion_id}} = vote,
         opinion_id,
         operation
       ) do
    opinion = Map.put(vote.opinion, :likes_count, operation.(vote.opinion.likes_count))
    Map.put(vote, :opinion, opinion)
  end

  defp replace_opinion_in_vote(vote, _, _), do: vote

  @spec page_title(atom, binary) :: binary
  defp page_title(:show, voting_title), do: voting_title
  defp page_title(:edit, _), do: "Edit Voting"

  defp load_random_votings(socket, voting_id) do
    assign(socket, :random_votings, Votings.list_random_votings(voting_id, 5))
  end
end
