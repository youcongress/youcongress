defmodule YouCongressWeb.VotingLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votings

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage voting records in your database.</:subtitle>
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
     |> assign_form(changeset)}
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
         |> redirect(to: ~p"/votings/#{voting.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
