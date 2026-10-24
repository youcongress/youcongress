defmodule YouCongressWeb.AuthorLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Accounts
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Authors
  alias YouCongress.Countries

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
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
        <.input
          field={@form[:country_id]}
          type="select"
          label="Country"
          prompt="Select country"
          options={@country_options}
        />
        <.input field={@form[:twin_origin]} type="checkbox" label="Is twin" />
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
     |> assign(:country_options, Countries.country_options())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"author" => author_params}, socket) do
    case authorize(socket, socket.assigns.action) do
      {:ok, _user} ->
        changeset =
          socket.assigns.author
          |> Authors.change_author(author_params)
          |> Map.put(:action, :validate)

        {:noreply, assign_form(socket, changeset)}

      {:error, :forbidden} ->
        deny_access(socket)
    end
  end

  def handle_event("save", %{"author" => author_params}, socket) do
    case authorize(socket, socket.assigns.action) do
      {:ok, user} -> save_author(socket, socket.assigns.action, user, author_params)
      {:error, :forbidden} -> deny_access(socket)
    end
  end

  defp save_author(socket, :edit, _user, author_params) do
    case Authors.update_author(socket.assigns.author, author_params) do
      {:ok, author} ->
        notify_parent({:saved, Authors.preload(author, [:country])})

        {:noreply,
         socket
         |> put_flash(:info, "Author updated successfully")
         |> redirect(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_author(socket, :new, user, author_params) do
    case Authors.create_author(user, author_params) do
      {:ok, author} ->
        notify_parent({:saved, Authors.preload(author, [:country])})

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

  defp authorize(socket, action) do
    with %{id: user_id} <- socket.assigns[:current_user],
         %{} = user <- Accounts.get_user(user_id),
         false <- Permissions.blocked?(user),
         true <- permitted?(action, user) do
      {:ok, user}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp permitted?(:new, user), do: Permissions.can_create_authors?(user)
  defp permitted?(_action, user), do: Permissions.can_edit_author?(user)

  defp deny_access(socket) do
    {:noreply,
     socket
     |> put_flash(:error, "You don't have permission to manage authors.")
     |> redirect(to: ~p"/")}
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
