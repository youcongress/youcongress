defmodule YouCongressWeb.ManifestoLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Manifestos

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage manifesto records.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="manifesto-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:active]} type="checkbox" label="Active" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Manifesto</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{manifesto: manifesto} = assigns, socket) do
    changeset = Manifestos.change_manifesto(manifesto)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"manifesto" => manifesto_params}, socket) do
    changeset =
      socket.assigns.manifesto
      |> Manifestos.change_manifesto(manifesto_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"manifesto" => manifesto_params}, socket) do
    save_manifesto(socket, socket.assigns.action, manifesto_params)
  end

  defp save_manifesto(socket, :new, manifesto_params) do
    case socket.assigns[:current_user] do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "You must log in to create a manifesto.")
         |> push_navigate(to: ~p"/log_in")}

      current_user ->
        params = Map.put(manifesto_params, "user_id", current_user.id)

        case Manifestos.create_manifesto(params) do
          {:ok, manifesto} ->
            notify_parent({:saved, manifesto})

            {:noreply,
             socket
             |> put_flash(:info, "Manifesto created successfully")
             |> push_patch(to: socket.assigns.patch)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign_form(socket, changeset)}
        end
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
