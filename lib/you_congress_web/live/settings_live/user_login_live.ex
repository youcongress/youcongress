defmodule YouCongressWeb.UserLoginLive do
  use YouCongressWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <div class="mt-6 space-y-3">
        <.link
          href={~p"/auth/google"}
          class="w-full inline-flex justify-center items-center py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-white text-gray-700 text-sm font-medium hover:bg-gray-50"
        >
          <svg class="w-5 h-5 mr-2" viewBox="0 0 24 24">
            <path
              fill="#4285F4"
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
            />
            <path
              fill="#34A853"
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
            />
            <path
              fill="#FBBC05"
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
            />
            <path
              fill="#EA4335"
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
            />
          </svg>
          Continue with Google
        </.link>
        <.link
          href={~p"/auth/x"}
          class="w-full inline-flex justify-center items-center py-2 px-4 border border-gray-300 rounded-md shadow-sm bg-black text-white text-sm font-medium hover:bg-gray-800"
        >
          <svg class="w-5 h-5 mr-2" viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
          Continue with X
        </.link>
      </div>

      <div class="mt-6">
        <div class="relative">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-gray-300"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="px-2 bg-white text-gray-500">or</span>
          </div>
        </div>
      </div>

      <%= unless @embedded do %>
        <.header class="text-center">
          Log in to account
          <:subtitle>
            Don't have an account? <.link href="/sign_up" class="underline">Sign up</.link>
          </:subtitle>
        </.header>
      <% end %>

      <.simple_form for={@form} id="login_form" action={~p"/log_in"} phx-update="ignore" class="mt-6">
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
        </:actions>
        <:actions>
          <%= if @pending_actions do %>
            <input type="hidden" name="user[pending_actions]" value={@pending_actions} />
          <% end %>
          <.button phx-disable-with="Signing in..." class="w-full bg-indigo-500 hover:bg-indigo-700">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center mt-4">
        <.link href={~p"/reset_password"} class="text-sm text-gray-600 hover:text-gray-900">
          Forgot your password?
        </.link>
      </p>
    </div>
    """
  end

  def mount(_params, session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")

    delegate_ids = session["delegate_ids"] || []
    votes = session["votes"] || %{}

    pending_actions =
      if delegate_ids != [] or map_size(votes) > 0 do
        Jason.encode!(%{delegate_ids: delegate_ids, votes: votes})
      else
        nil
      end

    {:ok,
     assign(socket,
       form: form,
       pending_actions: pending_actions,
       embedded: session["embedded"] || false
     ), temporary_assigns: [form: form]}
  end
end
