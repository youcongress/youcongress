defmodule YouCongressWeb.TopHeaderComponent do
  @moduledoc """
  The top header component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def top_header(assigns) do
    ~H"""
    <header class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between border-b border-zinc-100 py-3 text-sm">
        <div class="flex items-center gap-4">
          <a href="/">
            YouCongress
          </a>
        </div>

        <div class="flex items-center gap-4 font-semibold leading-6 text-zinc-900">
          <%= if @current_user do %>
            <div>
              <.link
                href={~p"/authors/#{@current_user.author_id}"}
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Profile
              </.link>
            </div>
          <% else %>
            <div>
              <.link
                href={~p"/log_in"}
                method="post"
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Log in with X
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </header>
    """
  end
end
