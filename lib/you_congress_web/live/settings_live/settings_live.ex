defmodule YouCongressWeb.SettingsLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Accounts.ApiKey
  alias YouCongress.{Accounts, Authors, Countries}

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_api_keys()
      |> assign_profile_author()
      |> assign_country_options()

    changeset =
      Authors.change_profile_author(
        socket.assigns.profile_author,
        profile_allowed_fields(socket.assigns.current_user)
      )

    {:ok, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("validate", %{"author" => author_params}, socket) do
    author_params = profile_author_params(author_params, socket)

    changeset =
      author(socket)
      |> Authors.change_profile_author(
        author_params,
        profile_allowed_fields(socket.assigns.current_user)
      )
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"author" => author_params}, socket) do
    author_params = profile_author_params(author_params, socket)

    case Authors.update_profile_author(
           author(socket),
           author_params,
           profile_allowed_fields(socket.assigns.current_user)
         ) do
      {:ok, author} ->
        {:noreply,
         socket
         |> assign_profile_author(Authors.preload(author, [:country]))
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

  defp assign_profile_author(socket) do
    assign_profile_author(socket, Authors.preload(socket.assigns.current_user.author, [:country]))
  end

  defp assign_profile_author(socket, author) do
    socket
    |> assign(:profile_author, author)
    |> assign(:profile_country_name, Authors.country_name(author))
  end

  defp assign_country_options(socket) do
    country_options =
      if phone_location_locked?(socket.assigns.current_user) do
        []
      else
        Countries.country_options()
      end

    assign(socket, :country_options, country_options)
  end

  defp author(socket), do: socket.assigns.profile_author

  defp profile_author_params(params, socket) when is_map(params) do
    allowed_fields = profile_allowed_fields(socket.assigns.current_user)
    allowed_keys = allowed_fields ++ Enum.map(allowed_fields, &Atom.to_string/1)

    Map.take(params, allowed_keys)
  end

  defp profile_allowed_fields(current_user) do
    current_user
    |> profile_text_fields()
    |> maybe_allow_country(current_user)
  end

  defp profile_text_fields(%{hashed_password: hashed_password}) when not is_nil(hashed_password),
    do: [:name, :bio]

  defp profile_text_fields(_current_user), do: []

  defp maybe_allow_country(fields, current_user) do
    if phone_location_locked?(current_user), do: fields, else: [:country_id | fields]
  end

  defp phone_location_locked?(%{phone_number_confirmed_at: confirmed_at}),
    do: not is_nil(confirmed_at)

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

  defp masked_token(%ApiKey{token: token}) when is_binary(token), do: masked_token(token)
  defp masked_token(%ApiKey{token_prefix: prefix}) when is_binary(prefix), do: "#{prefix}..."
  defp masked_token(nil), do: ""

  defp masked_token(token) do
    len = String.length(token)
    last = String.slice(token, max(len - 4, 0), len)
    prefix = if len > 4, do: "…", else: ""
    prefix <> last
  end
end
