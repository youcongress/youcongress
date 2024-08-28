defmodule YouCongressWeb.UserLoginLive do
  use YouCongressWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in to account
        <:subtitle>
          Don't have an account?
          <.link href="/x_log_in" method="post" class="underline">Sign up with X</.link>
          now or join the
          <.link href="/email-login-waiting-list" class="underline">
            waiting list
          </.link>
          for email/password login.
        </:subtitle>
      </.header>

      <.simple_form for={@form} id="login_form" action={~p"/log_in"} phx-update="ignore">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
          <.link href={~p"/reset_password"} class="text-sm font-semibold">
            Forgot your password?
          </.link>
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
      <div class="text-center pt-2">
        or
        <.link href="/x_log_in" method="post" class="w-full underline">
          log in with X
        </.link>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
