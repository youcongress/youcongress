defmodule YouCongressWeb.UserAuth do
  @moduledoc """
  Provides functions for authenticating users.
  """
  use YouCongressWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias YouCongress.Accounts
  alias YouCongressWeb.ReturnTo

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_you_congress_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> log_in_user_without_redirect(user, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  def log_in_user_without_redirect(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      YouCongressWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  @doc """
  Checks if the current user has a blocked role (spam or blocked)
  and logs them out if they do.
  """
  def reject_blocked_user(conn, _opts) do
    user = conn.assigns[:current_user]

    if YouCongress.Accounts.Permissions.blocked?(user) do
      user_token = get_session(conn, :user_token)
      user_token && Accounts.delete_user_session_token(user_token)

      if live_socket_id = get_session(conn, :live_socket_id) do
        YouCongressWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
      end

      conn
      |> renew_session()
      |> delete_resp_cookie(@remember_me_cookie)
      |> put_flash(
        :error,
        "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
      )
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  def redirect_to_user_registration_if_email_unconfirmed(conn, _opts) do
    user = conn.assigns[:current_user]

    allowed_paths = [
      ~p"/sign_up",
      ~p"/log_out",
      ~p"/terms",
      ~p"/privacy-policy"
    ]

    allow_prefix = ["/dev/mailbox", "/users/confirm/"]

    current = current_path(conn)
    current_path_only = URI.parse(current).path

    path_allowed? =
      current_path_only in allowed_paths or
        Enum.any?(allow_prefix, fn prefix -> String.starts_with?(current_path_only, prefix) end)

    if user && !Accounts.sign_up_complete?(user) && !path_allowed? do
      return_to = get_session(conn, :registration_return_to) || current

      conn
      |> redirect(to: ReturnTo.sign_up_path(return_to))
      |> halt()
    else
      conn
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Handles mounting and authenticating the current_user in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_user` - Assigns current_user
      to socket assigns based on user_token, or nil if
      there's no user_token or no matching user.

    * `:ensure_authenticated` - Authenticates the user from the session,
      and assigns the current_user to socket assigns based
      on user_token.
      Redirects to login page if there's no logged user.

    * `:redirect_if_user_is_authenticated` - Authenticates the user from the session.
      Redirects to signed_in_path if there's a logged user.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the current_user:

      defmodule YouCongressWeb.PageLive do
        use YouCongressWeb, :live_view

        on_mount {YouCongressWeb.UserAuth, :mount_current_user}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{YouCongressWeb.UserAuth, :ensure_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:refresh_current_user, _params, session, socket) do
    user_token = session["user_token"]
    socket = mount_current_user(socket, session)

    case authorize_refreshed_live_user(socket, socket.assigns.current_user) do
      {:cont, socket} ->
        socket =
          maybe_attach_event_hook(
            socket,
            :refresh_current_user,
            &refresh_current_user_on_event(user_token, &1, &2, &3)
          )

        {:cont, socket}

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    authorize_live_socket(
      socket,
      session["user_token"],
      :authenticated,
      &present?/1,
      "You must log in to access this page.",
      ~p"/log_in"
    )
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket))}
    else
      {:cont, socket}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end

  defp refresh_current_user_on_event(nil, _event, _params, socket) do
    authorize_refreshed_live_user(socket, nil)
  end

  defp refresh_current_user_on_event(user_token, _event, _params, socket) do
    authorize_refreshed_live_user(socket, Accounts.get_user_by_session_token(user_token))
  end

  defp authorize_refreshed_live_user(socket, user) do
    access = required_live_access(socket)

    cond do
      Accounts.Permissions.blocked?(user) ->
        {:halt, live_access_denied(socket, "Your account is blocked.", ~p"/")}

      access_allowed?(access, user) ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}

      access == :authenticated ->
        {:halt,
         live_access_denied(
           socket,
           "Your session has expired. Please log in again.",
           ~p"/log_in"
         )}

      true ->
        {:halt, live_access_denied(socket, access_denied_message(access), ~p"/")}
    end
  end

  defp authorize_live_socket(socket, user_token, hook_name, policy, message, path) do
    user = user_token && Accounts.get_user_by_session_token(user_token)

    if policy.(user) and !Accounts.Permissions.blocked?(user) do
      socket =
        socket
        |> Phoenix.Component.assign(:current_user, user)
        |> maybe_attach_event_hook(hook_name, fn _event, _params, socket ->
          refreshed_user = user_token && Accounts.get_user_by_session_token(user_token)

          if policy.(refreshed_user) and !Accounts.Permissions.blocked?(refreshed_user) do
            {:cont, Phoenix.Component.assign(socket, :current_user, refreshed_user)}
          else
            {:halt, live_access_denied(socket, message, path)}
          end
        end)

      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.Component.assign(:current_user, user)
       |> live_access_denied(message, path)}
    end
  end

  defp maybe_attach_event_hook(%{private: %{lifecycle: _}} = socket, name, callback) do
    Phoenix.LiveView.attach_hook(socket, name, :handle_event, callback)
  end

  defp maybe_attach_event_hook(socket, _name, _callback), do: socket

  defp required_live_access(%{view: YouCongressWeb.AuthorLive.Index}), do: :admin

  defp required_live_access(%{
         view: YouCongressWeb.AuthorLive.Show,
         assigns: %{live_action: :edit}
       }),
       do: :admin

  defp required_live_access(%{
         view: YouCongressWeb.StatementLive.Index,
         assigns: %{live_action: :new}
       }),
       do: :admin

  defp required_live_access(%{
         view: YouCongressWeb.StatementLive.Show,
         assigns: %{live_action: :edit}
       }),
       do: :admin

  defp required_live_access(%{view: YouCongressWeb.QuoteReviewLive.Index}),
    do: :admin_or_moderator

  defp required_live_access(%{view: YouCongressWeb.ReconsiderLive.New}),
    do: :creator_or_admin

  defp required_live_access(%{view: YouCongressWeb.WelcomeLive.Index}), do: :authenticated
  defp required_live_access(%{view: YouCongressWeb.StatementLive.AddQuote}), do: :authenticated
  defp required_live_access(%{view: YouCongressWeb.SettingsLive}), do: :authenticated
  defp required_live_access(%{view: YouCongressWeb.HomeLive.Index}), do: :authenticated

  defp required_live_access(_socket), do: :public

  defp access_allowed?(:public, _user), do: true
  defp access_allowed?(:authenticated, user), do: present?(user)
  defp access_allowed?(:admin, user), do: Accounts.admin?(user)
  defp access_allowed?(:admin_or_moderator, user), do: admin_or_moderator?(user)

  defp access_allowed?(:creator_or_admin, user),
    do: Accounts.Permissions.can_create_reconsideration?(user)

  defp access_denied_message(:admin), do: "You must be an admin to access this page."

  defp access_denied_message(:admin_or_moderator),
    do: "You must be an admin or moderator to access this page."

  defp access_denied_message(:creator_or_admin),
    do: "You must be a creator or admin to create a Reconsider page."

  defp live_access_denied(socket, message, path) do
    socket
    |> Phoenix.LiveView.put_flash(:error, message)
    |> Phoenix.LiveView.redirect(to: path)
  end

  defp present?(nil), do: false
  defp present?(_user), do: true

  defp admin_or_moderator?(%Accounts.User{role: role}) when role in ["admin", "moderator"],
    do: true

  defp admin_or_moderator?(_user), do: false

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      maybe_store_login_return_to(conn)
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/log_in")
      |> halt()
    end
  end

  def require_creator_or_admin_user(conn, _opts) do
    if YouCongress.Accounts.Permissions.can_create_reconsideration?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "You must be a creator or admin to create a Reconsider page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def require_admin_user(conn, _opts) do
    if YouCongress.Accounts.admin?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, "You must be an admin to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/log_in")
      |> halt()
    end
  end

  def require_admin_or_moderator_user(conn, _opts) do
    case conn.assigns[:current_user] do
      %YouCongress.Accounts.User{role: role} when role in ["admin", "moderator"] ->
        conn

      _ ->
        conn
        |> put_flash(:error, "You must be an admin or moderator to access this page.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/log_in")
        |> halt()
    end
  end

  @doc """
  Redirects to / if user is authenticated.
  """
  def redirect_home_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp maybe_store_login_return_to(%{method: "GET", request_path: "/log_in"} = conn) do
    return_to =
      [
        query_param(conn, "return_to"),
        referrer_return_to(conn)
      ]
      |> first_valid_return_to()

    case return_to do
      nil -> conn
      path -> put_session(conn, :user_return_to, path)
    end
  end

  defp maybe_store_login_return_to(conn), do: conn

  defp first_valid_return_to(candidates) do
    Enum.find_value(candidates, &ReturnTo.sanitize/1)
  end

  defp query_param(%{query_string: query_string}, key) when is_binary(query_string) do
    query_string
    |> Plug.Conn.Query.decode()
    |> Map.get(key)
  end

  defp query_param(_, _), do: nil

  defp referrer_return_to(conn) do
    conn
    |> get_req_header("referer")
    |> List.first()
    |> ReturnTo.from_same_origin_url(conn.host)
  end

  defp signed_in_path(_conn), do: ~p"/"
end
