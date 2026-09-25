defmodule YouCongressWeb.UserSessionController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongressWeb.UserAuth
  alias YouCongress.Accounts.Permissions
  alias YouCongress.RateLimiter
  alias YouCongressWeb.ReturnTo

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, nil)
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    login_allowed? =
      RateLimiter.allowed?(:password_login_identity, email, 10, 15 * 60) and
        RateLimiter.allowed?(:password_login_ip, client_ip(conn), 50, 15 * 60)

    user = if login_allowed?, do: Accounts.get_user_by_email(email)

    cond do
      not login_allowed? ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/log_in")

      user && Permissions.blocked?(user) ->
        # Check password to avoid timing attacks
        _ = User.valid_password?(user, password)

        conn
        |> put_flash(
          :error,
          "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
        )
        |> redirect(to: ~p"/log_in")

      user = Accounts.get_user_by_email_and_password(email, password) ->
        handle_pending_actions(user, user_params["pending_actions"])

        conn =
          conn
          |> maybe_put_user_return_to(user_params["return_to"])
          |> then(fn conn -> if info, do: put_flash(conn, :info, info), else: conn end)

        UserAuth.log_in_user(conn, user, user_params)

      true ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/log_in")
    end
  end

  def request_magic_link(conn, %{"user" => %{"email" => email} = user_params})
      when is_binary(email) do
    delivery_allowed? =
      RateLimiter.allowed?(:magic_link_email, email, 5, 60 * 60) and
        RateLimiter.allowed?(:magic_link_ip, client_ip(conn), 20, 60 * 60) and
        RateLimiter.allowed?(:magic_link_global, :global, 10_000, 24 * 60 * 60)

    if delivery_allowed? do
      case Accounts.get_user_by_email(email) do
        %User{} = user ->
          unless Permissions.blocked?(user) do
            Accounts.deliver_user_magic_login_instructions(user, fn token ->
              magic_login_url(conn, token, user_params["return_to"])
            end)
          end

        nil ->
          :ok
      end
    end

    conn
    |> put_flash(
      :info,
      "If an account exists for that email, we'll send a sign-in link shortly."
    )
    |> put_flash(:email, String.slice(email, 0, 160))
    |> redirect(to: ~p"/log_in")
  end

  def request_magic_link(conn, _params) do
    conn
    |> put_flash(
      :info,
      "If an account exists for that email, we'll send a sign-in link shortly."
    )
    |> redirect(to: ~p"/log_in")
  end

  def confirm_magic_link(conn, %{"token" => token} = params) do
    case Accounts.consume_magic_login_token(token) do
      {:ok, user} ->
        if Permissions.blocked?(user) do
          conn
          |> put_flash(:error, blocked_account_message())
          |> redirect(to: ~p"/log_in")
        else
          conn
          |> maybe_put_user_return_to(params["return_to"])
          |> UserAuth.log_in_user(user)
        end

      :error ->
        conn
        |> put_flash(:error, "This sign-in link is invalid or has expired.")
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_pending_actions(_user, nil), do: :ok

  defp handle_pending_actions(user, pending_json) do
    YouCongress.PendingActions.process(user, pending_json)
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end

  def live_login(conn, %{"token" => token} = params) do
    case Accounts.consume_live_login_token(token) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user_without_redirect(user)
        |> maybe_put_registration_return_to(params["return_to"])
        |> json(%{success: true})

      :error ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false})
    end
  end

  def live_login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false})
  end

  defp maybe_put_user_return_to(conn, return_to) do
    case ReturnTo.sanitize(return_to) do
      nil -> conn
      path -> put_session(conn, :user_return_to, path)
    end
  end

  defp maybe_put_registration_return_to(conn, return_to) do
    case ReturnTo.sanitize(return_to) do
      nil -> conn
      path -> put_session(conn, :registration_return_to, path)
    end
  end

  defp magic_login_url(conn, token, return_to) do
    query =
      %{}
      |> maybe_put_query_param(:return_to, ReturnTo.sanitize(return_to))

    url(conn, ~p"/log_in/magic-link/#{token}?#{query}")
  end

  defp maybe_put_query_param(query, _key, nil), do: query
  defp maybe_put_query_param(query, _key, ""), do: query
  defp maybe_put_query_param(query, key, value), do: Map.put(query, key, value)

  defp blocked_account_message do
    "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
  end

  defp client_ip(%Plug.Conn{remote_ip: remote_ip}) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end
end
