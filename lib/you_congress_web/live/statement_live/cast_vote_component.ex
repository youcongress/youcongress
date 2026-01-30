defmodule YouCongressWeb.StatementLive.CastVoteComponent do
  use YouCongressWeb, :live_component

  require Logger

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongress.Track
  alias YouCongressWeb.StatementLive.CastVoteComponent
  alias YouCongressWeb.StatementLive.ResultsComponent
  alias YouCongress.DelegationVotes
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongressWeb.StatementLive.Index.OpinateComponent
  @impl true
  def render(assigns) do
    ~H"""
    <div class="md:ml-0">
      <div class="flex space-x-2">
        <CastVoteComponent.button
          answer={:for}
          statement={@statement}
          user_vote_answer={if @current_user_vote, do: @current_user_vote.answer}
          myself={@myself}
        />
        <CastVoteComponent.button
          answer={:abstain}
          statement={@statement}
          user_vote_answer={if @current_user_vote, do: @current_user_vote.answer}
          myself={@myself}
        />
        <CastVoteComponent.button
          answer={:against}
          statement={@statement}
          user_vote_answer={if @current_user_vote, do: @current_user_vote.answer}
          myself={@myself}
        />

        <.clear_vote_button
          current_user_vote={@current_user_vote}
          myself={@myself}
          class="pt-3 pl-1 hidden md:block text-xs"
        />
      </div>
      <.clear_vote_button
        current_user_vote={@current_user_vote}
        myself={@myself}
        class="text-xs md:hidden"
      />
      <%= if @display_results do %>
        <ResultsComponent.horizontal_bar
          total_votes={@total_votes}
          vote_frequencies={@vote_frequencies}
        />

        <div :if={@page == :statements_index && @current_user} class="pt-4">
          <.live_component
            module={OpinateComponent}
            id={@id}
            statement={@statement}
            opinion={@current_user_opinion}
            vote={@current_user_vote}
            current_user={@current_user}
          />
        </div>

        <div :if={@page == :statements_index && !@current_user} class="pt-2">
          Read
          <.link href={~p"/p/#{@statement.slug}"} class="cursor-pointer underline">arguments</.link>
          or <.link href={~p"/sign_up"} class="cursor-pointer underline">sign up</.link>
          to add your own and/or save your vote.
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if assigns.display_results do
      {:ok, assign_results_variables(socket)}
    else
      {:ok, socket}
    end
  end

  attr :answer, :atom, required: true
  attr :statement, :map, required: true
  attr :label1, :string
  attr :label2, :string
  attr :user_vote_answer, :atom
  attr :myself, :string, required: true

  def button(assigns) do
    ~H"""
    <div>
      <button
        id={"#{@statement.id}-vote-#{@answer}"}
        phx-click="vote"
        phx-value-response={@answer}
        phx-target={@myself}
        class={"rounded-lg bg-#{ResultsComponent.response_color(@answer)}-700 h-10 w-16 flex md:p-4 flex-col justify-center items-center p-1 text-xs font-semibold text-white shadow-sm ring-1 ring-inset ring-#{ResultsComponent.response_color(@answer)}-500 hover:bg-#{ResultsComponent.response_color(@answer)}-800 #{if @user_vote_answer && @user_vote_answer != @answer, do: "opacity-40", else: ""}"}
      >
        <%= if assigns[:label1] && assigns[:label2] do %>
          <span class="block">
            {if @user_vote_answer == @answer, do: "✓ "}
            {@label1}
          </span>
          <span class="block">
            {@label2}
          </span>
        <% else %>
          {if @user_vote_answer == @answer, do: "✓ "}
          <span>{String.capitalize(to_string(@answer))}</span>
        <% end %>
      </button>
    </div>
    """
  end

  attr :current_user_vote, :any, required: true
  attr :myself, :any, required: true
  attr :class, :string, default: ""

  def clear_vote_button(assigns) do
    ~H"""
    <div :if={@current_user_vote && @current_user_vote.answer} class={@class}>
      <%= if @current_user_vote.direct do %>
        <button
          phx-click="delete-direct-vote"
          phx-target={@myself}
          class="text-sm"
        >
          Clear
        </button>
      <% else %>
        via delegates
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("vote", %{"response" => response}, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Please sign up so your vote is saved."})

    socket =
      socket
      |> assign(:display_results, true)
      |> assign_results_variables()
      |> assign(:current_user_vote, %Vote{answer: String.to_existing_atom(response)})

    {:noreply, socket}
  end

  def handle_event("vote", %{"response" => response}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        statement: statement
      }
    } = socket

    case Votes.create_or_update(%{
           statement_id: statement.id,
           answer: response,
           author_id: current_user.author_id,
           direct: true
         }) do
      {:ok, vote} ->
        vote = Votes.get_vote(vote.id, preload: [:opinion])
        send(self(), {:voted, vote})
        Track.event("Vote", current_user)

        socket =
          socket
          |> assign(:current_user_vote, vote)
          |> maybe_assign_results_variables()

        {:noreply, socket}

      {:error, error} ->
        Logger.error("Error creating vote: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "Error creating vote.")}
    end
  end

  def handle_event("delete-direct-vote", _, %{assigns: %{current_user: nil}} = socket) do
    socket =
      socket
      |> assign(:display_results, false)
      |> assign(:current_user_vote, nil)

    {:noreply, assign(socket, current_user_vote: nil)}
  end

  def handle_event(
        "delete-direct-vote",
        _,
        %{assigns: %{current_user_vote: %{opinion_id: nil}}} = socket
      ) do
    %{
      assigns: %{
        current_user_vote: current_user_vote,
        current_user: current_user,
        statement: statement
      }
    } = socket

    result = Votes.delete_vote(current_user_vote)

    case result do
      {:ok, _} ->
        Track.event("Delete Vote", current_user)

        DelegationVotes.update_author_statement_delegated_votes(
          current_user.author_id,
          current_user_vote.statement_id
        )

        # Load it in case she's delegating now
        vote =
          Votes.get_by(
            [author_id: current_user.author_id, statement_id: statement.id],
            preload: [:opinion]
          )

        send(self(), {:voted, vote})

        socket =
          socket
          |> assign(:current_user_vote, vote)
          |> maybe_assign_results_variables()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting vote.")}
    end
  end

  def handle_event("delete-direct-vote", _, socket) do
    extra =
      if socket.assigns.current_user_vote.answer == :abstain do
        ""
      else
        " Or just vote Abstain and keep the comment."
      end

    send(
      self(),
      {:put_flash, :error,
       "To delete your direct vote, you must first delete your comment.#{extra}"}
    )

    {:noreply, socket}
  end

  defp maybe_assign_results_variables(%{assigns: %{page: :statements_index}} = socket) do
    assign_results_variables(socket)
  end

  defp maybe_assign_results_variables(socket), do: socket

  defp assign_results_variables(socket) do
    %{assigns: %{statement: statement}} = socket

    socket
    |> assign(:display_results, true)
    |> assign(:vote_frequencies, VoteFrequencies.get(statement.id))
    |> assign(:total_votes, Votes.count_by_statement(statement.id))
  end
end
