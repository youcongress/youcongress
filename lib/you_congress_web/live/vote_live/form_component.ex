defmodule YouCongressWeb.VoteLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Votes

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage vote records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="vote-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:opinion]} type="text" label="Opinion" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Vote</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{vote: vote} = assigns, socket) do
    changeset = Votes.change_vote(vote)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"vote" => vote_params}, socket) do
    changeset =
      socket.assigns.vote
      |> Votes.change_vote(vote_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"vote" => vote_params}, socket) do
    save_vote(socket, socket.assigns.action, vote_params)
  end

  defp save_vote(socket, :edit, vote_params) do
    case Votes.update_vote(socket.assigns.vote, vote_params) do
      {:ok, vote} ->
        notify_parent({:saved, vote})

        {:noreply,
         socket
         |> put_flash(:info, "Vote updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_vote(socket, :new, vote_params) do
    case Votes.create_vote(vote_params) do
      {:ok, vote} ->
        notify_parent({:saved, vote})

        {:noreply,
         socket
         |> put_flash(:info, "Vote created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
