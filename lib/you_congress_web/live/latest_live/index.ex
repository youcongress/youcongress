defmodule YouCongressWeb.LatestLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.StatementQueries
  alias YouCongress.Track
  alias YouCongress.Votes
  alias YouCongressWeb.DateGroup
  alias YouCongressWeb.ReturnTo
  alias YouCongressWeb.StatementLive.VoteComponent

  @per_page 15
  @author_votes_limit 5

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:has_more_cards, true)
      |> assign(:cards, [])
      |> assign(:author_votes, %{})
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
      |> assign(:delegate_ids, current_user_delegation_ids(current_user))
      |> assign_cards(1)

    if connected?(socket) do
      Track.event("View Newest Opinions", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, url, socket) do
    socket =
      socket
      |> assign(:return_to, ReturnTo.from_url(url))
      |> assign(:page_title, "Newest Opinions")
      |> assign(
        :page_description,
        "The most recent sourced opinions, ordered by the date they were stated, together with each author's statements and votes."
      )
      |> assign(:noindex, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    if socket.assigns.has_more_cards do
      {:noreply, assign_cards(socket, socket.assigns.page + 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:put_flash, kind, msg}, socket) do
    socket =
      socket
      |> clear_flash()
      |> put_flash(kind, msg)

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp assign_cards(socket, page) do
    %{:per_page => per_page} = socket.assigns
    offset = (page - 1) * per_page

    cards = StatementQueries.get_newest_opinion_cards(offset: offset, limit: per_page)

    if cards == [] do
      assign(socket, :has_more_cards, false)
    else
      author_ids = cards |> Enum.map(& &1.vote.author_id) |> Enum.uniq()

      author_votes =
        Votes.list_recent_votes_by_author_ids(author_ids, limit: @author_votes_limit + 1)

      socket
      |> assign(:cards, socket.assigns.cards ++ cards)
      |> assign(:author_votes, Map.merge(socket.assigns.author_votes, author_votes))
      |> assign(:page, page)
      |> assign(:has_more_cards, length(cards) == per_page)
    end
  end

  @doc """
  Splits the loaded cards into date groups ("Today", "Yesterday", ...) so the
  feed renders as a timeline. Cards already arrive sorted by opinion date.
  """
  def date_groups(cards) do
    DateGroup.group(cards, &card_date/1)
  end

  defp card_date(%{vote: %{opinion: %Opinion{date: date, date_precision: precision}}}),
    do: {date, precision}

  defp card_date(_card), do: nil

  def author_votes(author_votes_by_id, author_id, statement_id) do
    author_votes_by_id
    |> Map.get(author_id, [])
    |> Enum.reject(&(&1.statement_id == statement_id))
    |> Enum.take(@author_votes_limit)
  end

  defp author_name(%{name: name}) when is_binary(name) and name != "", do: name

  defp author_name(%{twitter_username: username})
       when is_binary(username) and username != "",
       do: "x/#{username}"

  defp author_name(_author), do: "Anonymous"

  defp answer_badge(answer) do
    base_classes =
      "shrink-0 inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold"

    color_classes =
      case answer do
        :for -> "bg-green-100 text-green-800"
        :against -> "bg-red-100 text-red-800"
        :abstain -> "bg-blue-100 text-blue-800"
        _ -> "bg-gray-100 text-gray-800"
      end

    "#{base_classes} #{color_classes}"
  end

  defp answer_label(:for), do: "For"
  defp answer_label(:against), do: "Against"
  defp answer_label(:abstain), do: "Abstain"
  defp answer_label(answer), do: answer

  defp current_user_delegation_ids(nil), do: []

  defp current_user_delegation_ids(current_user) do
    Delegations.delegate_ids_by_deleguee_id(current_user.author_id)
  end

  defdelegate author_path(author), to: YouCongressWeb.SEO, as: :author_path
end
