defmodule YouCongressWeb.StatementLive.VoteComponent.QuoteMenu do
  @moduledoc """
  Displays links to:
  - I am this person!
  - Add a sourced quote
  """
  use Phoenix.Component

  alias YouCongress.Accounts.Permissions

  attr :id, :map, required: true
  attr :author, :map, required: true
  attr :opinion, :map, required: true
  attr :current_user, :map, required: true
  attr :statement, :map, required: true
  attr :page, :atom, required: true
  attr :myself, :map, default: nil

  def render(assigns) do
    ~H"""
    <div class="relative justify-end" phx-hook="QuoteMenu" id={"ai-menu-#{@id}"}>
      <button
        type="button"
        class="inline-flex items-center gap-x-1 text-sm font-semibold leading-6 text-gray-900"
        aria-expanded="false"
        title="Menu"
      >
        <svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 -960 960 960" width="24">
          <path d="M480-160q-33 0-56.5-23.5T400-240q0-33 23.5-56.5T480-320q33 0 56.5 23.5T560-240q0 33-23.5 56.5T480-160Zm0-240q-33 0-56.5-23.5T400-480q0-33 23.5-56.5T480-560q33 0 56.5 23.5T560-480q0 33-23.5 56.5T480-400Zm0-240q-33 0-56.5-23.5T400-720q0-33 23.5-56.5T480-800q33 0 56.5 23.5T560-720q0 33-23.5 56.5T480-640Z" />
        </svg>
      </button>
      <div class="hidden absolute right-0 z-10 mt-2 w-48 origin-top-right">
        <div class="w-48 shrink rounded-xl bg-white p-4 text-sm font-semibold leading-6 text-gray-900 shadow-lg ring-1 ring-gray-900/5">
          <%= if @opinion && (@opinion.twin || @opinion.source_url) && is_nil(@opinion.ancestry) do %>
            <.link href="/faq#my-profile" class="block py-1 px-2 hover:text-indigo-600">
              I am this person!
            </.link>
            <%= if @statement do %>
              <span class="block py-1 px-2">
                <.link
                  href={"/p/#{@statement.slug}/add-quote?twitter_username=#{@author.twitter_username}"}
                  class="hover:text-indigo-600"
                  rel="nofollow"
                >
                  Add a sourced quote
                </.link>
              </span>
            <% end %>
          <% end %>

          <.link
            href="mailto:hi@youcongress.org"
            target="_blank"
            class="block py-1 px-2 hover:text-indigo-600"
          >
            Report comment
          </.link>
          <%= if (@current_user && @opinion && @current_user.author_id == @opinion.author_id) || @page == :opinion_show && Permissions.can_edit_opinion?(@opinion, @current_user) do %>
            <.link
              phx-click="edit"
              phx-value-opinion_id={@opinion.id}
              class="block py-1 px-2 hover:text-indigo-600"
            >
              Edit comment
            </.link>
            <.link
              phx-click="delete-comment"
              phx-value-opinion_id={@opinion.id}
              class="block py-1 px-2 hover:text-indigo-600"
            >
              Delete comment
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
