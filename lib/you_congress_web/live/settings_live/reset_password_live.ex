defmodule YouCongressWeb.ResetPasswordLive do
  use YouCongressWeb, :live_view
  alias YouCongress.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Reset Password
        <:subtitle>
          Enter your email to receive a password reset link
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="reset_password_form" phx-submit="send_reset_instructions">
        <.input field={@form[:email]} type="email" label="Email" required />

        <:actions>
          <.button phx-disable-with="Sending..." class="w-full bg-indigo-500 hover:bg-indigo-700">
            Send Reset Instructions
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link href={~p"/log_in"}>Back to Log in</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    form = to_form(%{"email" => nil}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end

  def handle_event("send_reset_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply, socket |> put_flash(:info, info) |> redirect(to: ~p"/")}
  end
end
