defmodule YouCongressWeb.TopHeaderComponent do
  use Phoenix.Component
  use YouCongressWeb, :html

  def top_header(assigns) do
    ~H"""
    <header class="px-4 sm:px-6 lg:px-8">
      <div class="flex items-center justify-between border-b border-zinc-100 py-3 text-sm">
        <div class="flex items-center gap-4">
          <a href="/">
            <img src={~p"/images/logo.svg"} width="36" />
          </a>
        </div>
        <div class="flex items-center gap-4 font-semibold leading-6 text-zinc-900">
          <%= if @votes_count do %>
            <%= @votes_count %> votes (<%= @user_votes_count %> yours)
          <% end %>
          <%= if @current_user do %>
            <div class="text-[0.8125rem] leading-6 text-zinc-900">
              <%= @current_user.email %>
            </div>
            <div>
              <.link
                href={~p"/settings"}
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Settings
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
                href={~p"/sign_up"}
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Register
              </.link>
            </div>
            <div>
              <.link
                href={~p"/log_in"}
                class="text-[0.8125rem] leading-6 text-zinc-900 font-semibold hover:text-zinc-700"
              >
                Log in
              </.link>
            </div>
          <% end %>
        </div>
      </div>
    </header>
    """
  end
end
