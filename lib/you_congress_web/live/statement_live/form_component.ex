defmodule YouCongressWeb.StatementLive.FormComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Statements
  alias YouCongress.Repo
  alias YouCongressWeb.StatementLive.HallsInputComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="statement-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:title]} type="text" label="Title" />
        <.input field={@form[:slug]} type="text" label="Slug" />
        <.live_component module={HallsInputComponent} id="halls-input" form={@form} />
        <:actions>
          <.button phx-disable-with="Saving...">Save Statement</.button>

          <.link
            phx-click="delete"
            phx-target={@myself}
            data-confirm="Are you sure? This will permanently delete all votes and opinions."
          >
            Delete
          </.link>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{statement: statement} = assigns, socket) do
    statement = Repo.preload(statement, [:halls, :halls_statements])
    changeset = Statements.change_statement(statement)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)
     |> assign(statement: statement)}
  end

  @impl true
  def handle_event("validate", %{"statement" => statement_params}, socket) do
    changeset =
      socket.assigns.statement
      |> Statements.change_statement(statement_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"statement" => statement_params}, socket) do
    save_statement(socket, socket.assigns.action, statement_params)
  end

  def handle_event("delete", _, socket) do
    case Statements.delete_statement(socket.assigns.statement) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Statement deleted successfully")
         |> redirect(to: ~p"/")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp save_statement(socket, :edit, statement_params) do
    case Statements.update_statement(socket.assigns.statement, statement_params) do
      {:ok, statement} ->
        notify_parent({:saved, statement})

        {:noreply,
         socket
         |> put_flash(:info, "Statement updated successfully")
         |> push_patch(to: ~p"/p/#{statement.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_statement(socket, :new, statement_params) do
    case Statements.create_statement(statement_params) do
      {:ok, statement} ->
        notify_parent({:saved, statement})

        {:noreply,
         socket
         |> put_flash(:info, "Statement created successfully")
         |> redirect(to: ~p"/p/#{statement.slug}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
