defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Delegations
  alias YouCongress.Votings
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.Answers
  alias YouCongressWeb.VotingLive.Show.VotesLoader

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    %{assigns: %{current_user: current_user}} = socket

    if connected?(socket) do
      YouCongress.Track.event("View Voting", current_user)
    end

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug}, _, socket) do
    voting = Votings.get_voting_by_slug!(slug)

    socket =
      socket
      |> assign(:page_title, page_title(socket.assigns.live_action))
      |> assign(reload: false)
      |> VotesLoader.load_voting_and_votes(voting.id)
      |> load_random_votings(voting.id)

    current_user_vote = socket.assigns.current_user_vote
    socket = assign(socket, editing: !current_user_vote || !current_user_vote.opinion)

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
    |> YouCongress.Workers.PublicFiguresWorker.new()
    |> Oban.insert()

    YouCongress.Track.event("Generate AI opinions", socket.assigns.current_user)

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

    case Votes.next_vote(%{
           voting_id: voting.id,
           answer_id: answer_id,
           author_id: current_user.author_id
         }) do
      {:ok, :deleted} ->
        socket = VotesLoader.load_voting_and_votes(socket, socket.assigns.voting.id)
        %{assigns: %{current_user_vote: current_user_vote}} = socket

        socket =
          put_flash(
            socket,
            :info,
            "Your direct vote has been deleted.#{extra_delete_message(response(current_user_vote))}"
          )

        {:noreply, socket}

      {:ok, _} ->
        socket =
          socket
          |> VotesLoader.load_voting_and_votes(socket.assigns.voting.id)
          |> put_flash(
            :info,
            "You voted #{response}. Click again to delete your direct vote."
          )

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
  end

  def handle_event("post", %{"comment" => opinion}, socket) do
    YouCongressWeb.VotingLive.Show.Comments.post_event(opinion, socket)
  end

  def handle_event("cancel-edit", _, socket) do
    socket =
      socket
      |> assign(editing: false)
      |> clear_flash()

    {:noreply, socket}
  end

  def handle_event("delete-comment", _, socket) do
    YouCongressWeb.VotingLive.Show.Comments.delete_event(socket)
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
    deleguee_id = current_user.author_id
    delegate_id = String.to_integer(author_id)

    case Delegations.create_delegation(%{delegate_id: delegate_id, deleguee_id: deleguee_id}) do
      {:ok, _} ->
        YouCongress.Track.event("Delegate", current_user)

        socket =
          socket
          |> assign(:delegating?, true)
          |> put_flash(
            :info,
            "Added to your delegation list. You're voting as the majority of your delegates – unless you directly vote."
          )
          |> YouCongressWeb.VotingLive.Show.VotesLoader.assign_main_variables(
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
    deleguee_id = current_user.author_id
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
      {:ok, _} ->
        YouCongress.Track.event("Remove Delegate", current_user)

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

  defp extra_delete_message(nil), do: ""

  defp extra_delete_message("Agree"), do: " You now agree via your delegates."
  defp extra_delete_message("Disagree"), do: " You now disagree via your delegates."
  defp extra_delete_message("Abstain"), do: " You now abstain via your delegates."

  @spec response(Vote.t() | nil) :: binary | nil
  defp response(nil), do: nil

  defp response(vote) do
    Answers.basic_answer_id_response_map()[vote.answer_id]
  end

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  defp load_random_votings(socket, voting_id) do
    assign(socket, :random_votings, Votings.list_random_votings(voting_id, 5))
  end

  defp response_color("Strongly agree"), do: "green"
  defp response_color("Agree"), do: "green"
  defp response_color("Disagree"), do: "red"
  defp response_color("Strongly disagree"), do: "red"
  defp response_color(_), do: "gray"
end
