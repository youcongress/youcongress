defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Likes
  alias YouCongress.Votings
  alias YouCongressWeb.VotingLive.Show.VotesLoader
  alias YouCongressWeb.VotingLive.Show.CurrentUserVoteComponent
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.VotingLive.Show.Comments
  alias YouCongress.Track
  alias YouCongress.Workers.QuotatorWorker
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
      |> assign(:source_filter, nil)
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

  def handle_params(%{"slug" => slug}, "edit", socket) do
    voting = Votings.get_by!(slug: slug)
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, page_title(socket.assigns.live_action, voting.title))
      |> assign(
        :page_description,
        "Find agreement, understand disagreement."
      )
      |> assign(:voting, voting)
      |> assign(:current_user, current_user)

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}

  def handle_event("find-sourced-quotes", %{"voting_id" => voting_id}, socket) do
    voting_id = String.to_integer(voting_id)
    current_user = socket.assigns.current_user

    cond do
      Application.get_env(:you_congress, :environment) == :prod ->
        {:noreply, put_flash(socket, :error, "This feature is not available in production.")}

      is_nil(current_user) ->
        {:noreply, put_flash(socket, :error, "Please log in to find quotes.")}

      not Permissions.can_generate_ai_votes?(current_user) ->
        {:noreply, put_flash(socket, :error, "You don't have permission to find quotes.")}

      true ->
        %{voting_id: voting_id, user_id: current_user.id, num_times: 5}
        |> QuotatorWorker.new()
        |> Oban.insert()

        Track.event("Find quotes", current_user)

        Process.send_after(self(), :reload, 100)

        {:noreply, clear_flash(socket)}
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

  def handle_event("edit", _, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("filter-quotes", _, socket) do
    %{assigns: %{source_filter: source_filter, voting: voting}} = socket

    source_filter =
      case source_filter do
        nil -> :quotes
        :quotes -> nil
        :users -> :quotes
      end

    socket =
      socket
      |> assign(:source_filter, source_filter)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  def handle_event("filter-users", _, socket) do
    %{assigns: %{source_filter: source_filter, voting: voting}} = socket

    source_filter =
      case source_filter do
        nil -> :users
        :quotes -> :users
        :users -> nil
      end

    socket =
      socket
      |> assign(:source_filter, source_filter)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  def handle_event("filter-answer", %{"answer" => answer}, socket) do
    %{assigns: %{voting: voting}} = socket

    socket =
      socket
      |> assign(:answer_filter, answer)
      |> VotesLoader.load_voting_and_votes(voting.id)

    {:noreply, socket}
  end

  @impl true

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

  def handle_info({YouCongressWeb.VotingLive.FormComponent, {:saved, voting}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Voting updated successfully")
     |> push_patch(to: ~p"/p/#{voting.slug}")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @spec page_title(atom, binary) :: binary
  defp page_title(:show, voting_title), do: voting_title
  defp page_title(:edit, _), do: "Edit Poll"

  defp load_random_votings(socket, voting_id) do
    voting = Votings.get_voting!(voting_id, preload: [:halls])

    {random_votings_by_hall, _} =
      voting.halls
      |> Enum.reduce({[], [voting_id]}, fn hall, {acc_halls, exclude_ids} ->
        votings = HallsVotings.get_random_votings(hall.name, 5, exclude_ids)
        new_exclude_ids = exclude_ids ++ Enum.map(votings, & &1.id)
        {acc_halls ++ [{hall, votings}], new_exclude_ids}
      end)

    random_votings_by_hall =
      Enum.reject(random_votings_by_hall, fn {_hall, votings} -> Enum.empty?(votings) end)

    assign(socket, :random_votings_by_hall, random_votings_by_hall)
  end
end
