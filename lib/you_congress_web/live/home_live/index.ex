defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.AuthorLive.Show, as: AuthorShow
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Delegations

  @per_page 15

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Activity", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _, socket) do
    socket =
      socket
      |> load_opinions_and_votes()
      |> assign(
        page_title: "Home",
        page: 1
      )

    {:noreply, socket}
  end

  defp load_opinions_and_votes(socket) do
    %{assigns: %{current_user: current_user}} = socket

    opinions =
      Opinions.list_opinions(
        preload: [:voting, :author],
        twin: false,
        order_by: [desc: :id],
        limit: @per_page
      )

    votes = get_votes(opinions)

    assign(socket,
      # opinions is not a stream because we need to re-render OpinionComponent when we delegate
      opinions: opinions,
      votes: votes,
      current_user_delegation_ids: current_user_delegation_ids(current_user),
      no_more_opinions?: length(opinions) < @per_page
    )
  end

  defp current_user_delegation_ids(nil), do: []

  defp current_user_delegation_ids(%{id: current_user_id}) do
    Delegations.list_delegation_ids(deleguee_id: current_user_id)
  end

  defp get_votes(opinions) do
    voting_ids = Enum.map(opinions, & &1.voting_id)
    author_ids = Enum.map(opinions, & &1.author_id)

    votes = Votes.list_votes(voting_ids: voting_ids, author_ids: author_ids, preload: [:answer])

    votes =
      Enum.reduce(opinions, %{}, fn opinion, acc ->
        vote =
          Enum.find(votes, fn v ->
            v.voting_id == opinion.voting_id && v.author_id == opinion.author_id
          end)

        Map.put(acc, opinion.id, vote)
      end)

    votes
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to delegate.")}
  end

  def handle_event(
        "add-delegation",
        %{"author_id" => delegate_id, "opinion_id" => opinion_id},
        socket
      ) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(current_user_delegation_ids: current_user_delegation_ids(current_user))
          |> put_flash(:info, "Delegation added successfully.")

        send_update(YouCongressWeb.OpinionLive.OpinionComponent,
          id: opinion_id,
          delegating: true
        )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to add delegation.")}
    end
  end

  def handle_event(
        "remove-delegation",
        %{"author_id" => delegate_id, "opinion_id" => opinion_id},
        socket
      ) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(current_user_delegation_ids: current_user_delegation_ids(current_user))
          |> put_flash(:info, "Delegation removed successfully.")

        send_update(YouCongressWeb.OpinionLive.OpinionComponent,
          id: opinion_id,
          delegating: false
        )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to remove delegation.")}
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    %{assigns: %{page: page, votes: votes, opinions: opinions}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    new_opinions =
      Opinions.list_opinions(
        preload: [:voting, :author],
        twin: false,
        order_by: [desc: :id],
        limit: @per_page,
        offset: offset
      )

    votes = Map.merge(votes, get_votes(opinions))

    socket =
      assign(socket,
        opinions: opinions ++ new_opinions,
        votes: votes,
        page: new_page,
        no_more_opinions?: length(new_opinions) < @per_page
      )

    {:noreply, socket}
  end
end
