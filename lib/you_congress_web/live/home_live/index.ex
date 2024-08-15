defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Track
  alias YouCongress.Likes
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Delegations

  @per_page 15

  @impl true
  def mount(params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()
      |> assign(all: params["all"] == "true")

    if connected?(socket) do
      Track.event("View Activity", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _, socket) do
    %{assigns: %{current_user: current_user}} = socket

    socket =
      socket
      |> load_opinions_and_votes()
      |> assign(
        page_title: "Home",
        page: 1
      )
      |> assign(:liked_opinion_ids, Likes.get_liked_opinion_ids(current_user))

    {:noreply, socket}
  end

  defp load_opinions_and_votes(socket) do
    %{assigns: %{current_user: current_user, all: all}} = socket

    opinions = list_opinions(all)

    assign(socket,
      opinions: opinions,
      current_user_delegation_ids: current_user_delegation_ids(current_user),
      no_more_opinions?: length(opinions) < @per_page
    )
  end

  defp list_opinions(true) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      twin: false,
      order_by: [desc: :id],
      limit: @per_page
    )
  end

  defp list_opinions(false) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      ancestry: nil,
      order_by: :relevant,
      limit: @per_page
    )
  end

  defp list_opinions(true, offset) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      twin: false,
      order_by: [desc: :id],
      limit: @per_page,
      offset: offset
    )
  end

  defp list_opinions(false, offset) do
    Opinions.list_opinions(
      preload: [:voting, :author],
      ancestry: nil,
      order_by: :relevant,
      limit: @per_page,
      offset: offset
    )
  end

  defp current_user_delegation_ids(nil), do: []

  defp current_user_delegation_ids(%{id: current_user_id}) do
    Delegations.list_delegation_ids(deleguee_id: current_user_id)
  end

  def handle_event("like", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to like.")}
  end

  def handle_event("like", %{"opinion_id" => opinion_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        opinions: opinions,
        liked_opinion_ids: liked_opinion_ids
      }
    } = socket

    opinion_id = String.to_integer(opinion_id)

    case Likes.like(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:liked_opinion_ids, [opinion_id | liked_opinion_ids])
          |> assign(:opinions, update_opinion_likes_count(opinions, opinion_id, &(&1 + 1)))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to like opinion.")}
    end
  end

  def handle_event("unlike", %{"opinion_id" => opinion_id}, socket) do
    %{
      assigns: %{
        current_user: current_user,
        opinions: opinions,
        liked_opinion_ids: liked_opinion_ids
      }
    } = socket

    opinion_id = String.to_integer(opinion_id)

    case Likes.unlike(opinion_id, current_user) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:liked_opinion_ids, Enum.filter(liked_opinion_ids, &(&1 != opinion_id)))
          |> assign(:opinions, update_opinion_likes_count(opinions, opinion_id, &(&1 - 1)))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to unlike opinion.")}
    end
  end

  def handle_event("add-delegation", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "You must be logged in to delegate.")}
  end

  def handle_event("add-delegation", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.create_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(current_user_delegation_ids: current_user_delegation_ids(current_user))
          |> put_flash(:info, "Delegation added successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to add delegation.")}
    end
  end

  def handle_event("remove-delegation", %{"author_id" => delegate_id}, socket) do
    %{assigns: %{current_user: current_user}} = socket

    case Delegations.delete_delegation(current_user, delegate_id) do
      {:ok, _} ->
        socket =
          socket
          |> assign(current_user_delegation_ids: current_user_delegation_ids(current_user))
          |> put_flash(:info, "Delegation removed successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to remove delegation.")}
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    %{assigns: %{page: page, opinions: opinions, all: all}} = socket
    new_page = page + 1
    offset = (new_page - 1) * @per_page

    new_opinions = list_opinions(all, offset)

    socket =
      assign(socket,
        opinions: opinions ++ new_opinions,
        page: new_page,
        no_more_opinions?: length(new_opinions) < @per_page
      )

    {:noreply, socket}
  end

  defp update_opinion_likes_count(opinions, opinion_id, operation) do
    Enum.map(opinions, fn
      %Opinions.Opinion{id: ^opinion_id} = opinion ->
        Map.update!(opinion, :likes_count, operation)

      other ->
        other
    end)
  end
end
