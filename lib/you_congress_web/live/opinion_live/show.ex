defmodule YouCongressWeb.OpinionLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Track
  alias YouCongress.Delegations
  alias YouCongressWeb.OpinionLive.OpinionComponent
  alias YouCongress.Votings

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Opinion", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => opinion_id}, _, socket) do
    socket = load_opinion!(socket, opinion_id)
    %{assigns: %{opinion: opinion}} = socket
    parent_opinion = Opinion.parent(opinion)
    changeset = Opinions.change_opinion(%Opinions.Opinion{})

    socket = load_delegations(socket)

    {:noreply,
     socket
     |> assign(
       page_title: "Opinion",
       opinion: opinion,
       parent_opinion: parent_opinion,
       changeset: changeset
     )}
  end

  @impl true
  def handle_event("validate", %{"opinion" => opinion_params}, socket) do
    changeset =
      %Opinions.Opinion{}
      |> Opinions.change_opinion(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"opinion" => %{"content" => content}}, socket) do
    %{assigns: %{opinion: opinion, current_user: current_user}} = socket

    ancestry = if opinion.ancestry, do: "#{opinion.ancestry}/#{opinion.id}", else: "#{opinion.id}"

    opinion_params = %{
      "content" => content,
      "voting_id" => opinion.voting_id,
      "author_id" => current_user.author_id,
      "user_id" => current_user.id,
      "ancestry" => ancestry
    }

    case Opinions.create_opinion(opinion_params) do
      {:ok, _opinion} ->
        child_opinions =
          Opinions.list_opinions(
            ancestry: Opinion.path_str(opinion),
            preload: [:author],
            order_by: [desc: :id]
          )

        changeset = Opinions.change_opinion(%Opinions.Opinion{})

        {:noreply,
         socket
         |> put_flash(:info, "Opinion created successfully.")
         |> assign(child_opinions: child_opinions, changeset: changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  def handle_event("remove-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    case Delegations.delete_delegation(%{deleguee_id: current_user.id, delegate_id: author_id}) do
      {:ok, _} ->
        socket =
          socket
          |> load_opinion!(opinion.id)
          |> load_delegations()
          |> put_flash(:info, "Delegation removed successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to remove delegation.")}
    end
  end

  def handle_event("add-delegation", %{"author_id" => author_id}, socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    case Delegations.create_delegation(%{deleguee_id: current_user.id, delegate_id: author_id}) do
      {:ok, _} ->
        socket =
          socket
          |> load_opinion!(opinion.id)
          |> load_delegations()
          |> put_flash(:info, "Delegated successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Failed to delegate.")}
    end
  end

  def handle_event("delete-comment", %{"opinion_id" => opinion_id}, socket) do
    opinion = Opinions.get_opinion!(opinion_id)
    opinion_id = opinion.id
    voting_id = opinion.voting_id

    {_count, nil} =
      Opinions.delete_opinion_and_descendants(opinion)

    socket =
      socket
      |> redirect_or_load_variables(opinion_id, voting_id)
      |> put_flash(:info, "Opinion deleted successfully.")

    {:noreply, socket}
  end

  defp redirect_or_load_variables(%{assigns: %{opinion: %{id: id}}} = socket, id, voting_id) do
    voting = Votings.get_voting!(voting_id)
    redirect(socket, to: "/v/#{voting.slug}")
  end

  defp redirect_or_load_variables(socket, _, _voting_id) do
    socket
    |> load_opinion!(socket.assigns.opinion.id)
    |> load_delegations()
  end

  defp load_opinion!(socket, opinion_id) do
    opinion = Opinions.get_opinion!(opinion_id, preload: [:author, :voting])
    assign(socket, opinion: opinion)
  end

  defp load_delegations(socket) do
    %{assigns: %{current_user: current_user, opinion: opinion}} = socket

    child_opinions =
      Opinions.list_opinions(
        ancestry: Opinion.path_str(opinion),
        preload: [:author],
        order_by: [desc: :id]
      )

    delegating = Delegations.delegating?(current_user.author_id, opinion.author_id)
    delegate_ids = Delegations.list_delegation_ids(deleguee_id: current_user.author_id)

    child_opinions_delegations =
      child_opinions
      |> Enum.map(& &1.author_id)
      |> Enum.uniq()
      |> Enum.into(%{}, fn author_id ->
        {author_id, author_id in delegate_ids}
      end)

    assign(socket,
      delegating: delegating,
      child_opinions_delegations: child_opinions_delegations,
      child_opinions: child_opinions
    )
  end
end
