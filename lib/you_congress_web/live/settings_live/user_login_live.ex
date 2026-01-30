defmodule YouCongressWeb.UserLoginLive do
  use YouCongressWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <%= unless @embedded do %>
        <.header class="text-center">
          Log in to account
          <:subtitle>
            Don't have an account? <.link href="/sign_up" class="underline">Sign up</.link>
          </:subtitle>
        </.header>
      <% end %>

      <.simple_form for={@form} id="login_form" action={~p"/log_in"} phx-update="ignore">
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

      <div class="mt-6">
        <div class="relative">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-gray-300"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="px-2 bg-white text-gray-500">Or</span>
          </div>
        </div>

        <div class="mt-6">
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
      </div>
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
