defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.DigitalTwins
  alias YouCongress.Accounts.User
  alias YouCongress.Delegations
  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.Answers

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign_current_user(session["user_token"])
     |> assign(show_results: false)}
  end

  @impl true
  @spec handle_params(map, binary, Socket.t()) :: {:noreply, Socket.t()}
  def handle_params(%{"id" => voting_id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> load_voting_and_votes(voting_id)}
  end

  @impl true
  @spec handle_event(binary, map, Socket.t()) :: {:noreply, Socket.t()}
  def handle_event("generate-votes", %{"voting_id" => voting_id}, socket) do
    voting_id = String.to_integer(voting_id)
    Task.async(fn -> create_ai_opinions(voting_id, 5, socket) end)

    {:noreply,
     put_flash(
       socket,
       :info,
       "Generating five opinions. Please wait one minute and reload the page."
     )}
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

  @spec response(%Vote{} | nil) :: binary | nil
  defp response(nil), do: nil

  defp response(vote) do
    Answers.basic_answer_id_response_map()[vote.answer_id]
  end

  @spec create_ai_opinions(number, number, Socket.t()) :: :ok
  def create_ai_opinions(_, 0, _) do
    :ok
  end

  def create_ai_opinions(voting_id, n, socket) do
    {:ok, _vote} = DigitalTwins.generate_vote(voting_id)
    %{assigns: %{current_user: current_user}} = socket

    YouCongress.DelegationVotes.update_author_voting_delegated_votes(%{
      author_id: current_user.author_id,
      voting_id: voting_id
    })

    create_ai_opinions(voting_id, n - 1, socket)
  end

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  @spec load_voting_and_votes(Socket.t(), number) :: Socket.t()
  defp load_voting_and_votes(socket, voting_id) do
    voting = Votings.get_voting!(voting_id)
    votes = Votes.list_votes_with_opinion(voting_id, include: [:author, :answer])
    %{assigns: %{current_user: current_user}} = socket

    votes_from_delegates = get_votes_from_delegates(votes, current_user)
    vote_frequencies = get_vote_frequencies(voting)

    socket
    |> assign(
      voting: voting,
      votes_from_delegates: votes_from_delegates,
      votes_from_non_delegates: votes -- votes_from_delegates,
      current_user_vote: get_current_user_vote(voting, current_user),
      vote_frequencies: vote_frequencies
    )
    |> assign_counters()
  end

  @spec get_vote_frequencies(%Voting{}) :: %{binary => number}
  defp get_vote_frequencies(voting) do
    vote_frequencies =
      Votes.count_by_response(voting.id)
      |> Enum.into(%{})

    total = Enum.sum(Map.values(vote_frequencies))

    vote_frequencies
    |> Enum.map(fn {k, v} -> {k, {v, round(v * 100 / total)}} end)
    |> Enum.into(%{})
  end

  @spec get_votes_from_delegates([%Vote{}], %User{} | nil) :: [%Vote{}] | []
  defp get_votes_from_delegates(_, nil), do: []

  defp get_votes_from_delegates(votes, current_user) do
    delegate_ids = Delegations.delegate_ids_by_author_id(current_user.id)
    Enum.filter(votes, fn vote -> vote.author_id in delegate_ids end)
  end

  @spec get_current_user_vote(%Voting{}, %User{} | nil) :: %Vote{} | nil
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
end
