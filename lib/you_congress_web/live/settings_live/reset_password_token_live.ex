defmodule YouCongressWeb.ResetPasswordTokenLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">Reset Password</.header>

      <.simple_form for={@form} id="reset_password_form" phx-submit="reset_password">
        <.error :if={@form.errors != []}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={@form[:password]} type="password" label="New password" required />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          required
        />
        <:actions>
          <.button phx-disable-with="Resetting..." class="w-full bg-indigo-500 hover:bg-indigo-700">
            Reset Password
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link href={~p"/log_in"}>Log in</.link>
      </p>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      form =
        Accounts.change_user_password(user)
        |> to_form(as: "user")

      {:ok, assign(socket, form: form, token: token, user: user)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Reset password link is invalid or it has expired.")
       |> redirect(to: ~p"/")}
    end
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/log_in")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end
end
