defmodule YouCongressWeb.AuthorLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Authors

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage author records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="author-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Name" />
        <.input field={@form[:bio]} type="text" label="Bio" />
        <.input field={@form[:wikipedia_url]} type="text" label="Wikipedia url" />
        <.input field={@form[:twitter_username]} type="text" label="Twitter username" />
        <.input field={@form[:country]} type="text" label="Country" />
        <.input field={@form[:is_twin]} type="checkbox" label="Is twin" />
        <.input
          field={@form[:twin_enabled]}
          type="checkbox"
          label="Accept AI-generated content on my name. Unselect to delete current AI-gen opinions and disable future ones."
        />
        <:actions>
          <.button phx-disable-with="Saving...">Save Author</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{author: author} = assigns, socket) do
    changeset = Authors.change_author(author)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"author" => author_params}, socket) do
    changeset =
      socket.assigns.author
      |> Authors.change_author(author_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"author" => author_params}, socket) do
    save_author(socket, socket.assigns.action, author_params)
  end

  defp save_author(socket, :edit, author_params) do
    case Authors.update_author(socket.assigns.author, author_params) do
      {:ok, author} ->
        notify_parent({:saved, author})

        {:noreply,
         socket
         |> put_flash(:info, "Author updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_author(socket, :new, author_params) do
    case Authors.create_author(author_params) do
      {:ok, author} ->
        notify_parent({:saved, author})

        {:noreply,
         socket
         |> put_flash(:info, "Author created successfully")
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
