defmodule YouCongressWeb.AuthorLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors
  alias YouCongress.Delegations

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign_current_user(socket, session["user_token"])}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:author, Authors.get_author!(id, include: [votes: [:voting, :answer]]))
     |> assign_delegating?()}
  end

  @impl true
  def handle_event(
        "toggle-delegate",
        %{"author_id" => author_id},
        %{assigns: %{delegating?: true}} = socket
      ) do
    deleguee_id = socket.assigns.current_user.id
    delegate_id = String.to_integer(author_id)

    case Delegations.delete_delegation(%{deleguee_id: deleguee_id, delegate_id: delegate_id}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, false)
          |> put_flash(:info, "Delegation deleted successfully.")

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Error deleting delegation.")}
    end
  end

  def handle_event("toggle-delegate", %{"author_id" => delegate_id}, socket) do
    deleguee_id = socket.assigns.current_user.id

    case Delegations.create_delegation(%{delegate_id: delegate_id, deleguee_id: deleguee_id}) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:delegating?, true)
          |> put_flash(:info, "Delegation created successfully.")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Error creating delegation.")}
    end
  end

  defp page_title(:show), do: "Show Author"
  defp page_title(:edit), do: "Edit Author"

  defp assign_delegating?(%{assigns: %{current_user: nil}} = socket) do
    assign(socket, :delegating?, false)
  end

  @spec assign_delegating?(Socket.t()) :: Socket.t()
  defp assign_delegating?(%{assigns: %{author: author, current_user: current_user}} = socket) do
    delegating = Delegations.delegating?(current_user.id, author.id)
    assign(socket, :delegating?, delegating)
  end
end
