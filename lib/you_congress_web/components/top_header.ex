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
          <.link href={~p"/"}>
            YouCongress
          </.link>
        </div>

        <div class="text-sm flex items-center gap-3 leading-6 text-zinc-900">
          <div>
            <.link href="https://github.com/youcongress/youcongress" target="_blank">
              Open Source
            </.link>
          </div>
          <div class="hidden md:block">
            <.link href="https://x.com/arpahector" target="_blank">
              X/Twitter
            </.link>
          </div>

          <div>
            <.link href={~p"/about"}>
              About
            </.link>
          </div>
          <%= if @current_user do %>
            <div>
              <.link href={author_path(@current_user.author)}>
                Profile
              </.link>
            </div>
          <% else %>
            <div>
              <.link
                href={~p"/log_in"}
                method="post"
                class="text-[0.8125rem] leading-6 text-zinc-900 hover:text-zinc-700"
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
