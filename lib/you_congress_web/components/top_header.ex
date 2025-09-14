defmodule YouCongressWeb.TopHeaderComponent do
  @moduledoc """
  The top header component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  defdelegate author_path(path), to: YouCongressWeb.AuthorLive.Show, as: :author_path

  def top_header(assigns) do
    ~H"""
    <header class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between border-b border-zinc-100 py-3 text-sm">
        <div class="flex items-center gap-4">
          <.link href={~p"/"} class="text-lg font-semibold">
            YouCongress
          </.link>
        </div>
        <!-- Desktop Navigation -->
        <div class="hidden md:flex text-sm items-center gap-6 leading-6 text-zinc-900">
          <.link href={~p"/home"} class="px-3 py-2 hover:text-zinc-700 transition-colors">
            Home
          </.link>
          <.link href={~p"/about"} class="px-3 py-2 hover:text-zinc-700 transition-colors">
            About
          </.link>

          <%= if @current_user do %>
            <.link
              href={author_path(@current_user.author)}
              class="px-3 py-2 hover:text-zinc-700 transition-colors"
            >
              Profile
            </.link>
            <.link href={~p"/log_out"} class="px-3 py-2 hover:text-zinc-700 transition-colors">
              Log out
            </.link>
          <% else %>
            <.link
              href={~p"/sign_up"}
              class="px-3 py-2 bg-zinc-900 text-white rounded-md hover:bg-zinc-700 transition-colors"
            >
              Sign up
            </.link>
          <% end %>
        </div>
        <!-- Mobile Navigation (Optimized Touch Targets) -->
        <div class="md:hidden flex flex-col items-end gap-3 text-sm">
          <div class="flex items-center gap-4">
            <.link
              href={~p"/about"}
              class="px-1 py-3 text-zinc-900 hover:text-zinc-700 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
            >
              About
            </.link>
            <%= if @current_user do %>
              <.link
                href={author_path(@current_user.author)}
                class="px-1 py-3 text-zinc-900 hover:text-zinc-700 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
              >
                Profile
              </.link>
              <.link
                href={~p"/log_out"}
                class="px-1 py-3 text-zinc-600 hover:text-zinc-800 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
              >
                Logout
              </.link>
            <% else %>
              <.link
                href={~p"/sign_up"}
                class="px-1 py-3 rounded-md hover:bg-zinc-700 transition-colors min-w-[44px] text-center"
              >
                Sign up
              </.link>
            <% end %>
          </div>
        </div>
      </div>
    </header>
    """
  end
end
