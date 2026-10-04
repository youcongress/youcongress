defmodule YouCongressWeb.SettingsLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Accounts.ApiKey
  alias YouCongress.{Accounts, Authors, Countries}
  alias YouCongress.Newsletters

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_api_keys()
      |> assign_profile_author()
      |> assign_country_options()

    {:ok, assign_profile_forms(socket)}
  end

  @impl true
  def handle_event("validate_username", %{"author" => author_params}, socket) do
    {:noreply, validate_profile_form(socket, author_params, [:username])}
  end

  def handle_event("validate_profile", %{"author" => author_params}, socket) do
    {:noreply, validate_profile_form(socket, author_params, profile_fields(socket))}
  end

  def handle_event("save_username", %{"author" => author_params}, socket) do
    update_profile(socket, author_params, [:username], :username_form)
  end

  def handle_event("save_profile", %{"author" => author_params}, socket) do
    update_profile(socket, author_params, profile_fields(socket), :profile_form)
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

  def handle_event("revoke_api_key", %{"id" => id}, socket) do
    with {api_key_id, ""} <- Integer.parse(id),
         :ok <- Accounts.revoke_api_key_for_user(socket.assigns.current_user, api_key_id) do
      {:noreply,
       socket
       |> assign_api_keys()
       |> put_flash(:info, "API key revoked.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Unable to revoke that API key.")}
    end
  end

  def handle_event("subscribe_newsletter", _params, socket) do
    case Newsletters.subscribe_user(socket.assigns.current_user, "settings") do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, %{user | author: socket.assigns.current_user.author})
         |> put_flash(:info, "You are subscribed to YouCongress updates.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "We could not update your subscription.")}
    end
  end

  def handle_event("send_password_setup_instructions", _params, socket) do
    Accounts.deliver_user_reset_password_instructions(
      socket.assigns.current_user,
      &url(~p"/reset_password/#{&1}")
    )

    {:noreply,
     put_flash(
       socket,
       :info,
       "We sent a password setup link to #{socket.assigns.current_user.email}."
     )}
  end

  defp validate_profile_form(socket, author_params, allowed_fields) do
    changeset =
      author(socket)
      |> Authors.change_profile_author(
        profile_author_params(author_params, allowed_fields),
        allowed_fields
      )
      |> Map.put(:action, :validate)

    assign_profile_form(socket, allowed_fields, changeset)
  end

  defp update_profile(socket, author_params, allowed_fields, form_name) do
    author_params = profile_author_params(author_params, allowed_fields)

    case Authors.update_profile_author(
           author(socket),
           author_params,
           allowed_fields
         ) do
      {:ok, author} ->
        author = Authors.preload(author, [:country])

        {:noreply,
         socket
         |> assign_profile_author(author)
         |> assign(:current_user, %{socket.assigns.current_user | author: author})
         |> assign_profile_forms()
         |> put_flash(:info, "Settings updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form_name, to_form(changeset))}
    end
  end

  defp assign_profile_forms(socket) do
    socket
    |> assign_username_form(Authors.change_profile_author(author(socket), [:username]))
    |> assign_profile_form(
      profile_fields(socket),
      Authors.change_profile_author(author(socket), profile_fields(socket))
    )
  end

  defp assign_username_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :username_form, to_form(changeset))
  end

  defp assign_profile_form(socket, [:username], %Ecto.Changeset{} = changeset) do
    assign_username_form(socket, changeset)
  end

  defp assign_profile_form(socket, _allowed_fields, %Ecto.Changeset{} = changeset) do
    assign(socket, :profile_form, to_form(changeset))
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

  defp profile_author_params(params, allowed_fields) when is_map(params) do
    allowed_keys = allowed_fields ++ Enum.map(allowed_fields, &Atom.to_string/1)

    Map.take(params, allowed_keys)
  end

  defp profile_fields(socket) do
    profile_allowed_fields(socket.assigns.current_user) -- [:username]
  end

  defp profile_allowed_fields(current_user) do
    current_user
    |> profile_text_fields()
    |> then(&[:username | &1])
    |> maybe_allow_country(current_user)
  end

  defp profile_text_fields(%{hashed_password: hashed_password}) when not is_nil(hashed_password),
    do: [:name, :bio]

  defp profile_text_fields(%{signup_method: "email"}), do: [:name, :bio]

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
