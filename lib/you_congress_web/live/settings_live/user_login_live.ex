defmodule YouCongressWeb.UserLoginLive do
  use YouCongressWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in to account
        <:subtitle>
          Don't have an account? <.link href="/x_log_in" method="post" class="underline">Sign up with X</.link>*
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
        </:actions>
        <:actions>
          <.button phx-disable-with="Signing in..." class="w-full bg-indigo-500 hover:bg-indigo-700">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
      <div class="text-center">
        <div class="pb-1">or</div>
        <.link
          href="/x_log_in"
          method="post"
          class="inline-flex items-center justify-between bg-black text-white font-bold py-2 px-4 rounded-full hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-600 focus:ring-opacity-50 transition-colors duration-300"
        >
          Sign in with
          <svg
            class="w-5 h-5 ml-2"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="#ffffff"
          >
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
        </.link>*
      </div>
      <span class="text-xs">
        * If logging in with X fails, log in at
        <.link href="https://x.com" class="underline" target="_blank">x.com</.link>
        and then return here.
      </span>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
