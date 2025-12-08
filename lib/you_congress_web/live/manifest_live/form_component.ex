defmodule YouCongressWeb.ManifestLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Manifests

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage manifest records.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="manifest-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.input field={@form[:active]} type="checkbox" label="Active" />

        <:actions>
          <.button phx-disable-with="Saving...">Save Manifest</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{manifest: manifest} = assigns, socket) do
    changeset = Manifests.change_manifest(manifest)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"manifest" => manifest_params}, socket) do
    changeset =
      socket.assigns.manifest
      |> Manifests.change_manifest(manifest_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"manifest" => manifest_params}, socket) do
    save_manifest(socket, socket.assigns.action, manifest_params)
  end

  defp save_manifest(socket, :new, manifest_params) do
    current_user = socket.assigns[:current_user]
    params = if current_user, do: Map.put(manifest_params, "user_id", current_user.id), else: manifest_params

    case Manifests.create_manifest(params) do
      {:ok, manifest} ->
        notify_parent({:saved, manifest})

        {:noreply,
         socket
         |> put_flash(:info, "Manifest created successfully")
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
