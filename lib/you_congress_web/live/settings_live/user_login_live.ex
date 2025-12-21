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
