defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.Accounts.User
  alias YouCongress.Delegations
  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.Answers

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
      |> assign(show_results: false, reload: false)
      |> load_voting_and_votes(voting.id)
      |> load_random_votings(voting.id)

    if socket.assigns.voting.generating_left > 0 do
      Process.send_after(self(), :reload, 1_000)
    end

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate-votes", %{"voting_id" => voting_id}, socket) do
    voting_id = String.to_integer(voting_id)

    %{voting_id: voting_id, include_chatgpt_opinion: false}
    |> YouCongress.Workers.PublicFiguresWorker.new()
    |> Oban.insert()

    YouCongress.Track.event("Generate AI opinions", socket.assigns.current_user)

    Process.send_after(self(), :reload, 1_000)

    {:noreply, clear_flash(socket)}
  end

  def handle_event("toggle-results", _, socket) do
    {:noreply, assign(socket, :show_results, not socket.assigns.show_results)}
  end

  def handle_event("vote", %{"icon" => icon}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        voting: voting,
        current_user_vote: current_user_vote
      }
    } = socket

    response = next_response(icon, response(current_user_vote))
    answer_id = Answers.get_basic_answer_id(response)

    case Votes.next_vote(%{
           voting_id: voting.id,
           answer_id: answer_id,
           author_id: current_user.author_id
         }) do
      {:ok, :deleted} ->
        socket = load_voting_and_votes(socket, socket.assigns.voting.id)
        %{assigns: %{current_user_vote: current_user_vote}} = socket
        YouCongress.Track.event("Delete Vote", socket.assigns.current_user)

        socket =
          socket
          |> put_flash(
            :info,
            "Your direct vote has been deleted.#{extra_delete_message(response(current_user_vote))}"
          )

        {:noreply, socket}

      {:ok, _} ->
        YouCongress.Track.event("Vote", socket.assigns.current_user)

        socket =
          socket
          |> load_voting_and_votes(socket.assigns.voting.id)
          |> put_flash(:info, "You now #{message(response)}.")

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
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
        socket = load_voting_and_votes(socket, socket.assigns.voting.id)
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
          |> load_voting_and_votes(socket.assigns.voting.id)
          |> put_flash(
            :info,
            "You are now voting #{response}. Click again to delete your direct vote."
          )

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
  end

  def handle_event("reload", _, socket) do
    socket =
      socket
      |> load_voting_and_votes(socket.assigns.voting.id)
      |> assign(reload: false)
      |> clear_flash()

    {:noreply, socket}
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
          |> assign_main_variables(voting, current_user)
          |> assign(reload: true)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
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
          |> assign_main_variables(voting, current_user)
          |> assign(reload: true)

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  @impl true
  def handle_info(:reload, socket) do
    socket = load_voting_and_votes(socket, socket.assigns.voting.id)

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

  @spec next_response(binary, binary) :: binary
  defp next_response("tick", "Agree"), do: "Strongly agree"
  defp next_response("tick", "Strongly agree"), do: "Strongly agree"
  defp next_response("tick", _), do: "Agree"
  defp next_response("x", "Disagree"), do: "Strongly disagree"
  defp next_response("x", "Strongly disagree"), do: "Strongly disagree"
  defp next_response("x", _), do: "Disagree"
  defp next_response("abstain", _), do: "Abstain"
  defp next_response("no-comment", _), do: "N/A"

  defp message("Strongly agree"), do: "strongly agree. Click again to delete your direct vote"
  defp message("Agree"), do: "agree. Click again to strongly agree"
  defp message("Abstain"), do: "abstain. Click again to delete your direct vote"
  defp message("N/A"), do: "N/A. Click again to delete your direct vote"
  defp message("Disagree"), do: "disagree. Click again to strongly disagree"

  defp message("Strongly disagree"),
    do: "strongly disagree. Click again to delete your direct vote"

  @spec response(Vote.t() | nil) :: binary | nil
  defp response(nil), do: nil

  defp response(vote) do
    Answers.basic_answer_id_response_map()[vote.answer_id]
  end

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  @spec load_voting_and_votes(Socket.t(), number) :: Socket.t()
  defp load_voting_and_votes(socket, voting_id) do
    voting = Votings.get_voting!(voting_id)
    votes_with_opinion = Votes.list_votes_with_opinion(voting_id, include: [:author, :answer])
    %{assigns: %{current_user: current_user}} = socket

    votes_without_opinion =
      Votes.list_votes_without_opinion(voting_id, include: [:author, :answer])

    votes_generated = num_gen_opinions() - voting.generating_left
    percentage = round(votes_generated * 100 / num_gen_opinions())

    votes_from_delegates = get_votes_from_delegates(votes_with_opinion, current_user)

    socket
    |> assign(
      voting: voting,
      votes_from_delegates: votes_from_delegates,
      votes_from_non_delegates: votes_with_opinion -- votes_from_delegates,
      votes_without_opinion: votes_without_opinion,
      current_user_vote: get_current_user_vote(voting, current_user),
      percentage: percentage
    )
    |> assign_main_variables(voting, current_user)
  end

  defp assign_main_variables(socket, voting, current_user) do
    socket
    |> load_delegations(current_user)
    |> assign_counters()
    |> assign_vote_frequencies(voting)
    |> assign_current_user_vote(voting, current_user)
  end

  defp assign_current_user_vote(socket, voting, current_user) do
    assign(socket, current_user_vote: get_current_user_vote(voting, current_user))
  end

  defp assign_vote_frequencies(socket, voting) do
    assign(socket, vote_frequencies: get_vote_frequencies(voting))
  end

  defp load_random_votings(socket, voting_id) do
    assign(socket, :random_votings, Votings.list_random_votings(voting_id, 5))
  end

  defp load_delegations(socket, current_user) do
    %{
      assigns: %{
        votes_from_delegates: votes_from_delegates,
        votes_from_non_delegates: votes_from_non_delegates,
        votes_without_opinion: votes_without_opinion
      }
    } = socket

    author_ids =
      Enum.map(votes_from_delegates, & &1.author_id) ++
        Enum.map(votes_from_non_delegates, & &1.author_id) ++
        Enum.map(votes_without_opinion, & &1.author_id)

    delegate_ids = Delegations.delegate_ids_by_author_id(current_user.author_id)

    delegations =
      Enum.reduce(author_ids, %{}, fn author_id, acc ->
        Map.put(acc, author_id, !!Enum.find(delegate_ids, &(&1 == author_id)))
      end)

    assign(socket, delegations: delegations)
  end

  @spec get_vote_frequencies(Voting.t()) :: %{binary => number}
  defp get_vote_frequencies(voting) do
    vote_frequencies =
      Votes.count_by_response(voting.id)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(vote_frequencies))

    vote_frequencies
    |> Enum.map(fn {k, v} -> {k, {v, round(v * 100 / total)}} end)
    |> Enum.into(%{})
  end

  @spec get_votes_from_delegates([Vote.t()], User.t() | nil) :: [Vote.t()] | []
  defp get_votes_from_delegates(_, nil), do: []

  defp get_votes_from_delegates(votes, current_user) do
    delegate_ids = Delegations.delegate_ids_by_author_id(current_user.author_id)
    Enum.filter(votes, fn vote -> vote.author_id in delegate_ids end)
  end

  @spec get_current_user_vote(Voting.t(), User.t() | nil) :: Vote.t() | nil
  defp get_current_user_vote(_, nil), do: nil

  defp get_current_user_vote(voting, current_user) do
    Votes.get_vote([voting_id: voting.id, author_id: current_user.author_id], preload: :answer)
  end

  def agree_icon_size("Strongly agree"), do: 36
  def agree_icon_size("Agree"), do: 32
  def agree_icon_size(_), do: 24

  def disagree_icon_size("Strongly disagree"), do: 36
  def disagree_icon_size("Disagree"), do: 32
  def disagree_icon_size(_), do: 24

  def agree_icon_mt_css("Strongly agree"), do: nil
  def agree_icon_mt_css("Agree"), do: nil
  def agree_icon_mt_css(_), do: "mt-1"

  def disagree_icon_mt_css("Strongly disagree"), do: nil
  def disagree_icon_mt_css("Disagree"), do: nil
  def disagree_icon_mt_css(_), do: "mt-1"

  defp response_color("Strongly agree"), do: "green"
  defp response_color("Agree"), do: "green"
  defp response_color("Disagree"), do: "red"
  defp response_color("Strongly disagree"), do: "red"
  defp response_color(_), do: "gray"

  defp num_gen_opinions do
    YouCongress.DigitalTwins.PublicFigures.num_gen_opinions()
  end
end
