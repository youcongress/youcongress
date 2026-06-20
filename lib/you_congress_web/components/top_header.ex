defmodule YouCongressWeb.TopHeaderComponent do
  @moduledoc """
  The top header component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  alias YouCongressWeb.ReturnTo

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
          <.github_link />
          <.link
            :if={@current_user && YouCongress.Accounts.sign_up_complete?(@current_user)}
            href={~p"/"}
            class="px-3 py-2 hover:text-zinc-700 transition-colors"
          >
            Home
          </.link>
          <.link
            :if={!@current_user || YouCongress.Accounts.sign_up_complete?(@current_user)}
            href={~p"/about"}
            class="px-3 py-2 hover:text-zinc-700 transition-colors"
          >
            About
          </.link>

          <%= if @current_user do %>
            <.link
              :if={YouCongress.Accounts.sign_up_complete?(@current_user)}
              href={author_path(@current_user.author)}
              class="px-3 py-2 hover:text-zinc-700 transition-colors"
            >
              Profile
            </.link>
            <.link
              href={~p"/log_out"}
              method="delete"
              class="px-3 py-2 hover:text-zinc-700 transition-colors"
            >
              Log out
            </.link>
          <% else %>
            <.link
              href={ReturnTo.sign_up_path(@return_to)}
              class="px-3 py-2 bg-zinc-900 text-white rounded-md hover:bg-zinc-700 transition-colors"
            >
              Sign up
            </.link>
          <% end %>
        </div>
        <!-- Mobile Navigation (Optimized Touch Targets) -->
        <div class="md:hidden flex flex-col items-end gap-3 text-sm">
          <div class="flex items-center gap-4">
            <.github_link class="p-3" />
            <.link
              :if={!@current_user || YouCongress.Accounts.sign_up_complete?(@current_user)}
              href={~p"/about"}
              class="px-1 py-3 text-zinc-900 hover:text-zinc-700 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
            >
              About
            </.link>
            <%= if @current_user do %>
              <.link
                :if={YouCongress.Accounts.sign_up_complete?(@current_user)}
                href={author_path(@current_user.author)}
                class="px-1 py-3 text-zinc-900 hover:text-zinc-700 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
              >
                Profile
              </.link>
              <.link
                href={~p"/log_out"}
                method="delete"
                class="px-1 py-3 text-zinc-600 hover:text-zinc-800 hover:bg-zinc-50 rounded-md transition-colors min-w-[44px] text-center"
              >
                Logout
              </.link>
            <% else %>
              <.link
                href={ReturnTo.sign_up_path(@return_to)}
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

  attr :class, :string, default: "p-2"

  defp github_link(assigns) do
    ~H"""
    <.link
      href="https://github.com/youcongress/youcongress"
      target="_blank"
      rel="noopener noreferrer"
      aria-label="YouCongress on GitHub"
      class={[@class, "text-zinc-900 hover:text-zinc-600 transition-colors"]}
    >
      <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
        <path d="M12 2C6.477 2 2 6.477 2 12c0 4.419 2.865 8.166 6.839 9.489.5.092.682-.217.682-.48 0-.237-.009-.866-.014-1.699-2.782.604-3.369-1.341-3.369-1.341-.455-1.156-1.11-1.464-1.11-1.464-.908-.62.069-.608.069-.608 1.003.071 1.531 1.03 1.531 1.03.892 1.529 2.341 1.087 2.91.831.091-.646.349-1.087.635-1.337-2.221-.253-4.555-1.111-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.269.098-2.645 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0 1 12 6.838a9.59 9.59 0 0 1 2.504.337c1.909-1.294 2.748-1.025 2.748-1.025.545 1.376.202 2.392.099 2.645.64.699 1.028 1.592 1.028 2.683 0 3.842-2.337 4.687-4.566 4.935.359.309.679.92.679 1.855 0 1.338-.012 2.419-.012 2.747 0 .266.18.577.688.479C19.138 20.163 22 16.418 22 12c0-5.523-4.477-10-10-10Z" />
      </svg>
    </.link>
    """
  end
end
