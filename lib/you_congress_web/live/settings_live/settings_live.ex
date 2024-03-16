defmodule YouCongressWeb.SettingsLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Authors

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    changeset = Authors.change_author(author(socket))
    {:ok, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("validate", %{"author" => author_params}, socket) do
    changeset =
      author(socket)
      |> Authors.change_author(author_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"author" => author_params}, socket) do
    case Authors.update_author(author(socket), author_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Settings updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp author(socket), do: socket.assigns.current_user.author
end
