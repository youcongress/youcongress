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
      |> assign_content_variables()

    {:ok, socket}
  end

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    send(self(), {:put_flash, :warning, "Log in to like."})
    {:noreply, socket}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        opinion = Map.put(vote.opinion, :likes_count, vote.opinion.likes_count + 1)
        vote = Map.put(vote, :opinion, opinion)

        socket =
          socket
          |> assign(:liked, true)
          |> assign(:vote, vote)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error liking opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{assigns: %{current_user: current_user, vote: vote}} = socket
    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        opinion = Map.put(vote.opinion, :likes_count, vote.opinion.likes_count - 1)
        vote = Map.put(vote, :opinion, opinion)

        socket =
          socket
          |> assign(:liked, false)
          |> assign(:vote, vote)

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

  defp assign_content_variables(socket) do
    opinion = socket.assigns.vote.opinion

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
