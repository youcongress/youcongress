defmodule YouCongressWeb.LatestLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.QuotesCsv
  alias YouCongress.Statements.StatementQueries
  alias YouCongress.Track
  alias YouCongress.Votes
  alias YouCongressWeb.DateGroup
  alias YouCongressWeb.Components.SwitchComponent
  alias YouCongressWeb.ReturnTo
  alias YouCongressWeb.SEO
  alias YouCongressWeb.StatementLive.VoteComponent

  @per_page 15
  @author_votes_limit 5

  @impl true
  def mount(params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      |> assign(:has_more_cards, true)
      |> assign(:feed_order, feed_order_from_params(params))
      |> assign(:cards, [])
      |> assign(:author_votes, %{})
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))
      |> assign(:delegate_ids, current_user_delegation_ids(current_user))
      |> assign(:sourced_position_count, QuotesCsv.dataset_counts().quote_count)
      |> assign_cards(1)

    if connected?(socket) do
      Track.event("View Newest Opinions", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    feed_order = feed_order_from_params(params)

    socket =
      socket
      |> assign(:return_to, ReturnTo.from_url(url))
      |> assign(
        :page_title,
        "What's new in AI governance, safety, jobs and society | YouCongress"
      )
      |> assign(:skip_page_suffix, true)
      |> assign(
        :page_description,
        "Follow the latest sourced positions from experts, policymakers and public figures on AI governance, safety, jobs and society."
      )
      |> assign(:canonical_url, url(~p"/"))
      |> assign(:page_image, url(~p"/images/social-home.png"))
      |> assign(
        :page_image_alt,
        "YouCongress latest sourced positions from experts, policymakers and public figures"
      )
      |> assign(:page_image_width, 1731)
      |> assign(:page_image_height, 909)
      |> maybe_change_feed_order(feed_order)

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

  def handle_event("toggle-switch", _, socket) do
    path =
      if socket.assigns.feed_order == :quote_date,
        do: ~p"/?#{%{sort: "quote-added"}}",
        else: ~p"/"

    {:noreply, push_patch(socket, to: path)}
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

  defp feed_order_from_params(%{"sort" => "quote-added"}), do: :added
  defp feed_order_from_params(_params), do: :quote_date

  defp maybe_change_feed_order(%{assigns: %{feed_order: feed_order}} = socket, feed_order),
    do: socket

  defp maybe_change_feed_order(socket, feed_order) do
    socket
    |> assign(:feed_order, feed_order)
    |> assign(:cards, [])
    |> assign(:author_votes, %{})
    |> assign(:has_more_cards, true)
    |> assign_cards(1)
  end

  defp assign_cards(socket, page) do
    %{:per_page => per_page} = socket.assigns
    offset = (page - 1) * per_page

    cards =
      StatementQueries.get_newest_opinion_cards(
        offset: offset,
        limit: per_page,
        order_by: socket.assigns.feed_order
      )

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
  feed renders as a timeline. Cards already arrive sorted for the active mode.
  """
  def date_groups(cards, feed_order \\ :quote_date) do
    DateGroup.group(cards, &card_date(&1, feed_order))
  end

  defp card_date(
         %{vote: %{opinion: %Opinion{date: date, date_precision: precision}}},
         :quote_date
       ),
       do: {date, precision}

  defp card_date(%{vote: %{opinion: %Opinion{inserted_at: inserted_at}}}, :added),
    do: inserted_at_date(inserted_at)

  defp card_date(_card, _feed_order), do: nil

  defp inserted_at_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp inserted_at_date(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_date(datetime)
  defp inserted_at_date(_datetime), do: nil

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
