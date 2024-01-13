defmodule YouCongressWeb.VotingLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votings

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
      </.header>

      <.simple_form
        for={@form}
        id="voting-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Voting</.button>

          <.link
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Are you sure? This will permanently delete all votes and opinions in the poll."
          >
            Delete
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{voting: voting} = assigns, socket) do
    changeset = Votings.change_voting(voting)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign(voting: voting)}
  end

  @impl true
  def handle_event("validate", %{"voting" => voting_params}, socket) do
    changeset =
      socket.assigns.voting
      |> Votings.change_voting(voting_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"voting" => voting_params}, socket) do
    save_voting(socket, socket.assigns.action, voting_params)
  end

  def handle_event("delete", _, socket) do
    case Votings.delete_voting(socket.assigns.voting) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Voting deleted successfully")
         |> redirect(to: ~p"/")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp save_voting(socket, :edit, voting_params) do
    case Votings.update_voting(socket.assigns.voting, voting_params) do
      {:ok, voting} ->
        notify_parent({:saved, voting})

        {:noreply,
         socket
         |> put_flash(:info, "Voting updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_voting(socket, :new, voting_params) do
    case Votings.create_voting(voting_params) do
      {:ok, voting} ->
        notify_parent({:saved, voting})

        {:noreply,
         socket
         |> put_flash(:info, "Voting created successfully")
         |> redirect(to: ~p"/v/#{voting.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
