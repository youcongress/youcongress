defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Likes
  alias YouCongress.Votings
  alias YouCongress.DigitalTwins.Regenerate
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongressWeb.VotingLive.Show.VotesLoader
  alias YouCongressWeb.VotingLive.Show.CurrentUserVoteComponent
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.VotingLive.Show.Comments
  alias YouCongress.Track
  alias YouCongress.Workers.PublicFiguresWorker
  alias YouCongress.Accounts.Permissions
  alias YouCongressWeb.VotingLive.CastVoteComponent
  alias YouCongress.HallsVotings

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
    voting = Votings.get_by!(slug: slug)
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, page_title(socket.assigns.live_action, voting.title))
      |> assign(
        :page_description,
        "Find agreement, understand disagreement."
      )
      |> assign(reload: false)
      |> assign(:regenerating_opinion_id, nil)
      |> assign(:twin_filter, nil)
      |> assign(:answer_filter, nil)
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
    current_user = socket.assigns.current_user

    %{voting_id: voting_id, current_user_author_id: current_user.author_id}
    |> PublicFiguresWorker.new()
    |> Oban.insert()

    Track.event("Generate AI opinions", socket.assigns.current_user)

    Process.send_after(self(), :reload, 100)

    {:noreply, clear_flash(socket)}
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

  def handle_event("edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("filter-ai", _, socket) do
    %{assigns: %{twin_filter: twin_filter, voting: voting}} = socket

    twin_filter =
      case twin_filter do
        nil -> true
        true -> nil
        false -> true
      end

    socket =
      socket
      |> assign(:twin_filter, twin_filter)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  def handle_event("filter-human", _, socket) do
    %{assigns: %{twin_filter: twin_filter, voting: voting}} = socket

    twin_filter =
      case twin_filter do
        nil -> false
        true -> false
        false -> nil
      end

    socket =
      socket
      |> assign(:twin_filter, twin_filter)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  def handle_event("filter-answer", %{"answer" => answer}, socket) do
    %{assigns: %{voting: voting}} = socket
    IO.inspect(answer, label: "answer")

    socket =
      socket
      |> assign(:answer_filter, answer)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:regenerate, opinion_id}, socket) do
    %{assigns: %{current_user: current_user, voting: voting}} = socket

    case Regenerate.regenerate(opinion_id, current_user) do
      {:ok, {opinion, _vote}} ->
        opinion = Opinions.get_opinion(opinion.id, preload: [:author, :voting])

        socket =
          socket
          |> replace_opinion(opinion)
          |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user, voting))
          |> assign(:regenerating_opinion_id, nil)
          |> put_flash(:info, "Opinion regenerated.")

        {:noreply, socket}

      error ->
        Logger.debug("Error regenerating opinion. #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error regenerating opinion.")}
    end
  end

  def handle_info(:reload, socket) do
    socket = VotesLoader.load_voting_and_votes(socket, socket.assigns.voting.id)

    if socket.assigns.voting.generating_left > 0 do
      Process.send_after(self(), :reload, 1_000)
    end

    {:noreply, socket}
  end

  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info({:voted, vote}, socket) do
    {:noreply, assign(socket, :current_user_vote, vote)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp replace_opinion(socket, opinion) do
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
      Enum.map(votes_from_delegates, &replace_opinion_in_vote(&1, opinion))
    )
    |> assign(
      :votes_from_non_delegates,
      Enum.map(
        votes_from_non_delegates,
        &replace_opinion_in_vote(&1, opinion)
      )
    )
    |> assign(
      :current_user_vote,
      replace_opinion_in_vote(current_user_vote, opinion)
    )
  end

  defp replace_opinion_in_vote(
         %{opinion: %{id: opinion_id}} = vote,
         %Opinion{id: opinion_id} = opinion
       ) do
    Map.put(vote, :opinion, opinion)
  end

  defp replace_opinion_in_vote(vote, _), do: vote

  @spec page_title(atom, binary) :: binary
  defp page_title(:show, voting_title), do: voting_title
  defp page_title(:edit, _), do: "Edit Voting"

  defp load_random_votings(socket, voting_id) do
    voting = Votings.get_voting!(voting_id, preload: [:halls])

    {random_votings_by_hall, _} =
      voting.halls
      |> Enum.reduce({[], [voting_id]}, fn hall, {acc_halls, exclude_ids} ->
        votings = HallsVotings.get_random_votings(hall.name, 5, exclude_ids)
        new_exclude_ids = exclude_ids ++ Enum.map(votings, & &1.id)
        {acc_halls ++ [{hall, votings}], new_exclude_ids}
      end)

    random_votings_by_hall = Enum.reject(random_votings_by_hall, fn {_hall, votings} -> Enum.empty?(votings) end)
    assign(socket, :random_votings_by_hall, random_votings_by_hall)
  end
end
