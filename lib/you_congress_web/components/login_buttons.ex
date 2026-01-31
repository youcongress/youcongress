defmodule YouCongressWeb.Components.LoginButtons do
  @moduledoc """
  A component that renders login buttons for Google, X, and email/password.
  Used to prompt non-logged users to log in after voting.
  """

  use Phoenix.Component
  use YouCongressWeb, :verified_routes

  attr :message, :string, default: "Log in to save your vote:"
  attr :class, :string, default: ""

  def render(assigns) do
    ~H"""
    <div class={@class}>
      <p class="text-sm text-gray-600 mb-3">{@message}</p>
      <div class="flex flex-wrap gap-2">
        <.link
          href={~p"/auth/google"}
          class="inline-flex items-center py-1.5 px-3 border border-gray-300 rounded-md shadow-sm bg-white text-gray-700 text-sm font-medium hover:bg-gray-50"
        >
          <svg class="w-4 h-4 mr-1.5" viewBox="0 0 24 24">
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
          Google
        </.link>
        <.link
          href={~p"/auth/x"}
          class="inline-flex items-center py-1.5 px-3 border border-gray-300 rounded-md shadow-sm bg-black text-white text-sm font-medium hover:bg-gray-800"
        >
          <svg class="w-4 h-4 mr-1.5" viewBox="0 0 24 24" fill="currentColor">
            <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
          </svg>
          X
        </.link>
        <.link
          href={~p"/log_in"}
          class="inline-flex items-center py-1.5 px-3 text-sm text-gray-600 hover:text-indigo-600 hover:underline"
        >
          Email/password
        </.link>
      </div>
    </div>
    """
  end
end
