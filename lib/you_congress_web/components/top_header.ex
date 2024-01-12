defmodule YouCongressWeb.TopHeaderComponent do
  @moduledoc """
  The top header component.
  """

  use Phoenix.Component
  use YouCongressWeb, :html

  def top_header(assigns) do
    ~H"""
    <div class="mx-auto w-full text-xs py-1 text-center bg-yellow-50">
      All votes are public. Choose a list of delegates to vote according to the majority of them – unless you vote directly.
    </div>
    <header class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between border-b border-zinc-100 py-3 text-sm">
        <div class="flex items-center gap-4">
          <a href="/">
            YouCongress
          </a>
        </div>

        <div class="flex items-center gap-4 font-semibold leading-6 text-zinc-900">
          <%= if assigns[:votes_count] && assigns[:user_votes_count] do %>
            <div class="hidden md:block">
              <%= @votes_count %> votes (<.link href={~p"/authors/#{@current_user.author_id}"}><%= @user_votes_count %> yours</.link>)
            </div>
          <% end %>
          <%= if @current_user do %>
            <div class="hidden md:block text-[0.8125rem] leading-6 text-zinc-900">
              <.link href={~p"/authors/#{@current_user.author_id}"}>
                <%= @current_user.email %>
              </.link>
            </div>
            <div>
              <.link
                href={~p"/log_out"}
                method="delete"
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Log out
              </.link>
            </div>
          <% else %>
            <div>
              <.link
                href={~p"/log_in"}
                method="post"
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Log in with X/Twitter
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </header>
    """
  end
end
