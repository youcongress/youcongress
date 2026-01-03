defmodule YouCongressWeb.VotingLive.CastVoteComponent do
  use YouCongressWeb, :live_component

  require Logger

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.CastVoteComponent
  alias YouCongressWeb.VotingLive.ResultsComponent
  alias YouCongress.DelegationVotes
  alias YouCongress.Votes.VoteFrequencies
  alias YouCongressWeb.VotingLive.Index.OpinateComponent
  @impl true
  def render(assigns) do
    ~H"""
    <div class="-ml-2 md:ml-0">
      <div class="flex">
        <CastVoteComponent.button
          voting={@voting}
          response="For"
          current_user_vote={@current_user_vote}
          current_user={@current_user}
          myself={@myself}
          button_id="vote-for"
        />
        <CastVoteComponent.button
          voting={@voting}
          response="Abstain"
          current_user_vote={@current_user_vote}
          current_user={@current_user}
          myself={@myself}
          button_id="vote-abstain"
        />
        <CastVoteComponent.button
          voting={@voting}
          response="Against"
          current_user_vote={@current_user_vote}
          current_user={@current_user}
          myself={@myself}
          button_id="vote-against"
        />

        <%= if @current_user_vote && @current_user_vote.answer do %>
          <%= if @current_user_vote.direct do %>
            <div class="pt-3 pl-1 hidden md:block text-xs">
              <button phx-click="delete-direct-vote" phx-target={@myself} class="text-sm">
                Clear
              </button>
            </div>
          <% else %>
            <div class="pt-3 pl-1 hidden md:block text-xs">
              via delegates
            </div>
          <% end %>
        <% end %>
      </div>
      <%= if @current_user_vote && @current_user_vote.answer do %>
        <%= if @current_user_vote.direct do %>
          <div class="text-xs md:hidden">
            <button phx-click="delete-direct-vote" phx-target={@myself} class="text-sm">
              Clear
            </button>
          </div>
        <% else %>
          <div class="text-xs md:hidden">
            via delegates
          </div>
        <% end %>
      <% end %>
      <%= if @display_results do %>
        <ResultsComponent.horizontal_bar
          total_votes={@total_votes}
          vote_frequencies={@vote_frequencies}
        />

        <div :if={@page == :votings_index && @current_user} class="pt-4">
          <.live_component
            module={OpinateComponent}
            id={@id}
            voting={@voting}
            opinion={@current_user_opinion}
            vote={@current_user_vote}
            current_user={@current_user}
          />
        </div>

        <div :if={@page == :votings_index && !@current_user} class="pt-2">
          Read <.link href={~p"/p/#{@voting.slug}"} class="cursor-pointer underline">arguments</.link>
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

  attr :response, :string, required: true
  attr :voting, :map, required: true
  attr :label1, :string
  attr :label2, :string
  attr :current_user_vote, :map, required: true
  attr :current_user, :map, required: true
  attr :button_id, :string, required: true
  attr :myself, :string, required: true

  def button(assigns) do
    ~H"""
    <div class="pr-1">
      <button
        id={"#{@voting.id}-#{@button_id}"}
        phx-click="vote"
        phx-value-response={String.downcase(@response)}
        phx-target={@myself}
        class={"rounded-lg bg-#{ResultsComponent.response_color(@response)}-500 h-12 w-14 md:w-20 flex md:p-4 flex-col justify-center items-center p-1 text-xs font-semibold text-white shadow-sm ring-1 ring-inset ring-#{ResultsComponent.response_color(@response)}-300 hover:bg-#{ResultsComponent.response_color(@response)}-600"}
      >
        <%= if assigns[:label1] && assigns[:label2] do %>
          <div>
            {if @current_user_vote &&
                  @current_user_vote.answer == String.downcase(@response) |> String.to_existing_atom(),
                do: "✓ "}
            {@label1}
          </div>
          <div>
            {@label2}
          </div>
        <% else %>
          {if @current_user_vote &&
                @current_user_vote.answer == String.downcase(@response) |> String.to_existing_atom(),
              do: "✓ "}
          <div>{@response}</div>
        <% end %>
      </button>
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
        voting: voting
      }
    } = socket

    case Votes.create_or_update(%{
           voting_id: voting.id,
           answer: response,
           author_id: current_user.author_id,
           direct: true
         }) do
      {:ok, vote} ->
        vote = Votes.get_vote(vote.id, preload: [:opinion])
        send(self(), {:voted, vote})
        send(self(), {:put_flash, :info, "You voted #{String.capitalize(response)}."})
        Track.event("Vote", current_user)

        socket =
          socket
          |> assign(:current_user_vote, vote)
          |> assign_results_variables()

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

  def handle_event("delete-direct-vote", _, socket) do
    %{
      assigns: %{current_user_vote: current_user_vote, current_user: current_user, voting: voting}
    } = socket

    result = Votes.delete_vote(current_user_vote)

    case result do
      {:ok, _} ->
        Track.event("Delete Vote", current_user)

        DelegationVotes.update_author_voting_delegated_votes(
          current_user.author_id,
          current_user_vote.voting_id
        )

        # Load it in case she's delegating now
        vote =
          Votes.get_by(
            [author_id: current_user.author_id, voting_id: voting.id],
            preload: [:opinion]
          )

        send(self(), {:voted, vote})

        socket =
          socket
          |> assign(:current_user_vote, vote)
          |> assign_results_variables()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error deleting vote.")}
    end
  end

  defp assign_results_variables(socket) do
    %{assigns: %{voting: voting}} = socket

    socket
    |> assign(:display_results, true)
    |> assign(:vote_frequencies, VoteFrequencies.get(voting.id))
    |> assign(:total_votes, Votes.count_by_voting(voting.id))
  end
end
