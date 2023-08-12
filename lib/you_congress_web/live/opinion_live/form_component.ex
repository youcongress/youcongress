defmodule YouCongressWeb.OpinionLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Opinions

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage opinion records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="opinion-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:opinion]} type="text" label="Opinion" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Opinion</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{opinion: opinion} = assigns, socket) do
    changeset = Opinions.change_opinion(opinion)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"opinion" => opinion_params}, socket) do
    changeset =
      socket.assigns.opinion
      |> Opinions.change_opinion(opinion_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"opinion" => opinion_params}, socket) do
    save_opinion(socket, socket.assigns.action, opinion_params)
  end

  defp save_opinion(socket, :edit, opinion_params) do
    case Opinions.update_opinion(socket.assigns.opinion, opinion_params) do
      {:ok, opinion} ->
        notify_parent({:saved, opinion})

        {:noreply,
         socket
         |> put_flash(:info, "Opinion updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_opinion(socket, :new, opinion_params) do
    case Opinions.create_opinion(opinion_params) do
      {:ok, opinion} ->
        notify_parent({:saved, opinion})

        {:noreply,
         socket
         |> put_flash(:info, "Opinion created successfully")
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
