defmodule YouCongressWeb.SettingsLive do
  use YouCongressWeb, :live_view

  alias YouCongress.{Accounts, Authors}

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_api_keys()

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

  def handle_event("create_api_key", %{"api_key" => api_key_params}, socket) do
    case Accounts.create_api_key_for_user(socket.assigns.current_user, api_key_params) do
      {:ok, api_key} ->
        {:noreply,
         socket
         |> assign(:api_keys, [api_key | socket.assigns.api_keys])
         |> assign(:last_api_key_token, api_key.token)
         |> assign_api_key_form(Accounts.change_api_key())
         |> put_flash(:info, "API key created. Copy it now, you won't see it again.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_api_key_form(socket, changeset)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You must be signed in to manage API keys")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp assign_api_keys(socket) do
    socket
    |> assign(:api_keys, Accounts.list_api_keys_for_user(socket.assigns.current_user))
    |> assign(:last_api_key_token, nil)
    |> assign_api_key_form(Accounts.change_api_key())
  end

  defp assign_api_key_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :api_key_form, to_form(changeset))
  end

  defp author(socket), do: socket.assigns.current_user.author

  defp human_scope(scope) when is_atom(scope) do
    scope
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp human_scope(scope) when is_binary(scope) do
    scope
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp masked_token(nil), do: ""

  defp masked_token(token) do
    len = String.length(token)
    last = String.slice(token, max(len - 4, 0), len)
    prefix = if len > 4, do: "…", else: ""
    prefix <> last
  end
end
