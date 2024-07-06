defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.Track
  alias YouCongressWeb.VotingLive.VoteComponent
  alias YouCongressWeb.AuthorLive.Show, as: AuthorShow

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
    opinions =
      Opinions.list_opinions(
        preload: [:voting, :author],
        twin: false,
        order_by: [desc: :updated_at],
        limit: @per_page
      )

    votes = get_votes(opinions)

    socket
    |> stream(:opinions, opinions)
    |> assign(votes: votes)
    |> assign(no_more_opinions?: length(opinions) < @per_page)
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

  @impl true
  def handle_event("load-more", _, socket) do
    %{assigns: %{page: page, votes: votes}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    opinions =
      Opinions.list_opinions(
        preload: [:voting, :author],
        twin: false,
        order_by: [desc: :updated_at],
        limit: @per_page,
        offset: offset
      )

    votes = Map.merge(votes, get_votes(opinions))

    socket =
      socket
      |> stream(:opinions, opinions)
      |> assign(votes: votes)
      |> assign(page: new_page, no_more_opinions?: length(opinions) < @per_page)

    {:noreply, socket}
  end
end
