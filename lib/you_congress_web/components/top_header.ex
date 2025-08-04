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
          <.link href={~p"/home"}>
            AI polls
          </.link>
          <.link href={~p"/about"}>
            About
          </.link>

          <%= if @current_user do %>
            <.link href={author_path(@current_user.author)}>
              Profile
            </.link>
            <.link href={~p"/log_out"}>
              Log out
            </.link>
          <% else %>
            <.link
              href={~p"/sign_up"}
              class="text-[0.8125rem] leading-6 text-zinc-900 hover:text-zinc-700"
            >
              Sign up
            </.link>
          <% end %>
        </div>
      </div>
    </header>
    """
  end
end
