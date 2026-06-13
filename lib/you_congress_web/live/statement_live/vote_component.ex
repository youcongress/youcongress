defmodule YouCongressWeb.StatementLive.VoteComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Delegations
  alias YouCongress.Likes
  alias YouCongressWeb.Tools.Tooltip
  alias YouCongressWeb.StatementLive.VoteComponent.QuoteMenu
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongressWeb.Tools.TimeAgo

  @max_length 250

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:expanded, fn -> false end)
      |> assign_new(:visible_opinion_id, fn -> nil end)
      |> assign_visible_opinion()
      |> assign_opinion_statement()
      |> assign_content_variables()

    {:ok, socket}
  end

  # The relevance link for the vote's own quote on this statement, used by the
  # aggregate verification badge. The badge is about the vote's quote (the one the
  # answer is bound to), not whichever alternate is currently being read.
  defp assign_opinion_statement(socket) do
    %{vote: vote, statement: statement} = socket.assigns
    opinion = vote_opinion(vote)

    opinion_statement =
      if opinion && opinion.source_url && statement do
        YouCongress.OpinionsStatements.get_opinion_statement(opinion.id, statement.id)
      end

    assign(socket, :opinion_statement, opinion_statement)
  end

  defp vote_opinion(%{opinion: %YouCongress.Opinions.Opinion{} = opinion}), do: opinion
  defp vote_opinion(_), do: nil

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to like."})
    {:noreply, socket}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, visible_opinion: visible_opinion}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, :liked} ->
        visible_opinion = Map.put(visible_opinion, :likes_count, visible_opinion.likes_count + 1)

        socket =
          socket
          |> put_visible_opinion(visible_opinion)
          |> assign_liked(true)
          |> notify_liked_opinion(true)
          |> assign_content_variables()

        {:noreply, socket}

      {:ok, :already_liked} ->
        socket =
          socket
          |> assign_liked(true)
          |> notify_liked_opinion(true)
          |> assign_content_variables()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error liking opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, visible_opinion: visible_opinion}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, :unliked} ->
        visible_opinion =
          Map.put(visible_opinion, :likes_count, max(visible_opinion.likes_count - 1, 0))

        socket =
          socket
          |> put_visible_opinion(visible_opinion)
          |> assign_liked(false)
          |> notify_liked_opinion(false)
          |> assign_content_variables()

        {:noreply, socket}

      {:ok, :already_unliked} ->
        socket =
          socket
          |> assign_liked(false)
          |> notify_liked_opinion(false)
          |> assign_content_variables()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error unliking opinion.")}
    end
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    send(
      self(),
      {:put_flash, :warning, "Log in to unlock delegate voting."}
    )

    {:noreply, socket}
  end

  def handle_event("add-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        send(
          self(),
          {:put_flash, :info,
           "Added to your delegation list. You're voting as the majority of your delegates – unless you directly vote."}
        )

        socket =
          socket
          |> assign(:delegating?, true)
          |> assign(:reload, true)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  def handle_event("remove-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to remove your delegates."})
    socket = assign(socket, :delegating?, false)
    {:noreply, socket}
  end

  def handle_event("remove-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, false)
          |> assign(:reload, true)

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  def handle_event("toggle-expand", _, socket) do
    socket =
      socket
      |> assign(:expanded, !socket.assigns.expanded)
      |> assign_content_variables()

    {:noreply, socket}
  end

  def handle_event("previous-opinion", _, socket) do
    {:noreply, shift_visible_opinion(socket, -1)}
  end

  def handle_event("next-opinion", _, socket) do
    {:noreply, shift_visible_opinion(socket, 1)}
  end

  defp assign_visible_opinion(socket) do
    opinions = opinion_options(socket.assigns.vote)
    count = length(opinions)

    index = visible_opinion_index(opinions, socket.assigns.visible_opinion_id)

    visible_opinion = Enum.at(opinions, index)

    socket
    |> assign(:opinion_options, opinions)
    |> assign(:opinion_count, count)
    |> assign(:visible_opinion_index, index)
    |> assign(:visible_opinion_position, index + 1)
    |> assign(:visible_opinion_id, visible_opinion && visible_opinion.id)
    |> assign(:visible_opinion, visible_opinion)
    |> assign_liked_for_visible_opinion()
  end

  defp opinion_options(%{opinion: nil}), do: []

  defp opinion_options(%{alternate_opinions: opinions, opinion: opinion})
       when is_list(opinions) and opinions != [] do
    if Enum.any?(opinions, &(&1.id == opinion.id)) do
      opinions
    else
      [opinion | opinions]
    end
  end

  defp opinion_options(%{opinion: opinion}), do: [opinion]

  defp visible_opinion_index([], _visible_opinion_id), do: 0

  defp visible_opinion_index(opinions, visible_opinion_id) do
    opinion_index(opinions, visible_opinion_id) || 0
  end

  defp opinion_index(_opinions, nil), do: nil

  defp opinion_index(opinions, opinion_id) do
    Enum.find_index(opinions, &(&1.id == opinion_id))
  end

  defp shift_visible_opinion(%{assigns: %{opinion_count: count}} = socket, _shift)
       when count <= 1,
       do: socket

  defp shift_visible_opinion(socket, shift) do
    index =
      Integer.mod(socket.assigns.visible_opinion_index + shift, socket.assigns.opinion_count)

    socket
    |> assign(:visible_opinion_id, Enum.at(socket.assigns.opinion_options, index).id)
    |> assign(:expanded, false)
    |> assign_visible_opinion()
    |> assign_content_variables()
  end

  defp put_visible_opinion(socket, opinion) do
    opinion_options =
      Enum.map(socket.assigns.opinion_options, fn
        %{id: id} when id == opinion.id -> opinion
        other -> other
      end)

    vote =
      if socket.assigns.vote.opinion_id == opinion.id do
        Map.put(socket.assigns.vote, :opinion, opinion)
      else
        socket.assigns.vote
      end

    socket
    |> assign(:vote, vote)
    |> assign(:opinion_options, opinion_options)
    |> assign(:visible_opinion_id, opinion.id)
    |> assign(:visible_opinion, opinion)
  end

  defp assign_liked(socket, liked) do
    socket =
      if Map.has_key?(socket.assigns, :liked_opinion_ids) do
        liked_opinion_ids =
          if liked do
            Enum.uniq([socket.assigns.visible_opinion.id | socket.assigns.liked_opinion_ids])
          else
            Enum.reject(
              socket.assigns.liked_opinion_ids,
              &(&1 == socket.assigns.visible_opinion.id)
            )
          end

        assign(socket, :liked_opinion_ids, liked_opinion_ids)
      else
        socket
      end

    assign(socket, :liked, liked)
  end

  defp notify_liked_opinion(
         %{assigns: %{page: :statement_show, visible_opinion: opinion}} = socket,
         liked
       )
       when not is_nil(opinion) do
    send(self(), {:opinion_like_changed, opinion.id, liked})
    socket
  end

  defp notify_liked_opinion(socket, _liked), do: socket

  defp assign_liked_for_visible_opinion(%{assigns: %{visible_opinion: nil}} = socket), do: socket

  defp assign_liked_for_visible_opinion(socket) do
    liked =
      if Map.has_key?(socket.assigns, :liked_opinion_ids) do
        socket.assigns.visible_opinion.id in socket.assigns.liked_opinion_ids
      else
        Map.get(socket.assigns, :liked, false) &&
          socket.assigns.visible_opinion.id == socket.assigns.vote.opinion_id
      end

    assign(socket, :liked, liked)
  end

  defp assign_content_variables(socket) do
    opinion = socket.assigns.visible_opinion

    if opinion do
      content = opinion.content || ""
      expanded = socket.assigns.expanded

      if String.length(content) > @max_length and not expanded do
        socket
        |> assign(:truncated_content, String.slice(content, 0, @max_length) <> "...")
        |> assign(:show_more, true)
      else
        socket
        |> assign(:truncated_content, content)
        |> assign(:show_more, false)
      end
    else
      socket
      |> assign(:truncated_content, "")
      |> assign(:show_more, false)
    end
  end

  defp added_at(%{inserted_at: inserted_at}, _vote) when not is_nil(inserted_at) do
    inserted_at
  end

  defp added_at(_opinion, vote), do: vote.inserted_at

  defdelegate author_path(path), to: YouCongressWeb.AuthorLive.Show, as: :author_path

  defp response(assigns, response) do
    response_text = response(response)

    assigns =
      assign(assigns, color: response_color(response), response: response_text)

    ~H"""
    <span class={"#{@color} font-bold"}>
      {@response}
    </span>
    """
  end

  def response_with_s(assigns, response) do
    assigns =
      assign(assigns, color: response_color(response), response: with_s(response))

    ~H"""
    <span class={"#{@color} font-bold"}>
      {@response}
    </span>
    """
  end

  defp response(:for), do: "vote For"
  defp response("for"), do: "vote For"
  defp response(:against), do: "vote Against"
  defp response("against"), do: "vote Against"
  defp response(:abstain), do: "Abstain"
  defp response("abstain"), do: "Abstain"
  defp response(val), do: to_string(val)

  defp with_s(:for), do: "votes For"
  defp with_s("for"), do: "votes For"
  defp with_s(:against), do: "votes Against"
  defp with_s("against"), do: "votes Against"
  defp with_s(:abstain), do: "abstains"
  defp with_s("abstain"), do: "abstains"
  defp with_s(val), do: to_string(val)

  defp response_color(:for), do: "text-green-800"
  defp response_color("for"), do: "text-green-800"
  defp response_color(:against), do: "text-red-800"
  defp response_color("against"), do: "text-red-800"
  defp response_color(:abstain), do: "text-blue-800"
  defp response_color("abstain"), do: "text-blue-800"
  defp response_color(_), do: "text-gray-800"
end
