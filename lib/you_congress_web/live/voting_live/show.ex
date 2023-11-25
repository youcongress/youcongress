defmodule YouCongressWeb.VotingLive.Show do
  alias Phoenix.LiveView.Socket
  use YouCongressWeb, :live_view

  require Logger

  alias YouCongress.DigitalTwins
  alias YouCongress.Accounts.User
  alias YouCongress.Votings
  alias YouCongress.Votings.Voting
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_current_user(socket, session["user_token"])}
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
    send(self(), {:generate_vote, voting_id, 3})
    {:noreply, put_flash(socket, :info, "Generating votes...")}
  end

  def handle_event("vote", %{"icon" => icon}, socket) do
    %{
      assigns: %{
        current_user: author,
        voting: voting,
        current_user_response: current_user_response
      }
    } = socket

    response = next_response(icon, current_user_response)
    answer_id = Answers.get_basic_answer_id(response)

    case Votes.next_vote(%{voting_id: voting.id, answer_id: answer_id, author_id: author.id}) do
      {:ok, :deleted} ->
        socket =
          socket
          |> load_voting_and_votes(socket.assigns.voting.id)
          |> put_flash(:info, "Your vote has been deleted.")

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

  defp next_response("tick", "Agree"), do: "Strongly agree"
  defp next_response("tick", "Strongly agree"), do: "Strongly agree"
  defp next_response("tick", _), do: "Agree"
  defp next_response("x", "Disagree"), do: "Strongly disagree"
  defp next_response("x", "Strongly disagree"), do: "Strongly disagree"
  defp next_response("x", _), do: "Disagree"

  defp message("Strongly agree"), do: "strongly agree. Click again to delete your vote"
  defp message("Agree"), do: "agree. Click again to strongly agree"
  defp message("Disagree"), do: "disagree. Click again to strongly disagree"
  defp message("Strongly disagree"), do: "strongly disagree. Click again to delete your vote"

  @impl true
  @spec handle_info({:generate_vote, number, number}, Socket.t()) :: {:noreply, Socket.t()}
  def handle_info({:generate_vote, _voting_id, 0}, socket) do
    {:noreply, socket}
  end

  def handle_info({:generate_vote, voting_id, n}, socket) do
    {:ok, _vote} = DigitalTwins.generate_vote(voting_id)

    socket =
      socket
      |> load_voting_and_votes(voting_id)
      |> put_flash(:info, "Vote generated")

    send(self(), {:generate_vote, voting_id, n - 1})

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @spec page_title(atom) :: binary
  defp page_title(:show), do: "Show Voting"
  defp page_title(:edit), do: "Edit Voting"

  @spec load_voting_and_votes(Socket.t(), number) :: Socket.t()
  defp load_voting_and_votes(socket, voting_id) do
    voting = Votings.get_voting!(voting_id)
    votes = Votes.list_votes_with_opinion(voting_id, include: [:author, :answer])
    %{assigns: %{current_user: current_user}} = socket

    socket
    |> assign(
      voting: voting,
      votes: votes,
      current_user_response: get_current_user_response(voting, current_user)
    )
    |> assign_counters()
  end

  @spec get_current_user_response(%Voting{}, %User{} | nil) :: binary
  defp get_current_user_response(_, nil), do: nil

  defp get_current_user_response(voting, current_user) do
    case Votes.get_vote(voting_id: voting.id, author_id: current_user.id) do
      nil -> nil
      vote -> Answers.basic_answer_id_response_map()[vote.answer_id]
    end
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

  def agree_icon(%{current_user_response: nil} = assigns) do
    ~H"""
    <svg
      class="mt-1"
      phx-click="vote"
      phx-value-response="Agree"
      xmlns="http://www.w3.org/2000/svg"
      height="24"
      viewBox="0 -960 960 960"
      width="24"
    >
      <path d="M382-240 154-468l57-57 171 171 367-367 57 57-424 424Z" />
    </svg>
    """
  end

  def agree_icon(%{current_user_response: "Agree"} = assigns) do
    ~H"""
    <svg
      phx-click="vote"
      phx-value-response="Agree"
      xmlns="http://www.w3.org/2000/svg"
      height="32"
      viewBox="0 -960 960 960"
      width="32"
    >
      <%= agree_path(assigns) %>
    </svg>
    """
  end

  defp agree_path(assigns) do
    ~H"""
    <path d="M382-240 154-468l57-57 171 171 367-367 57 57-424 424Z" />
    """
  end
end
