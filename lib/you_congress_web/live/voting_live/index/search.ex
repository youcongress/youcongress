defmodule YouCongressWeb.VotingLive.Index.Search do
  @moduledoc """
  Search motions, delegates, halls, and quotes
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.VotingLive.Index.Search

  defdelegate author_path(path), to: YouCongressWeb.AuthorLive.Show, as: :author_path

  attr :search_tab, :atom, required: true
  attr :votings, :map, required: true
  attr :authors, :map, required: true
  attr :halls, :map, required: true
  attr :quotes, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="border-b border-gray-200 pt-4">
      <div class="pb-2">
        <nav class="-mb-px grid grid-cols-2 md:flex md:space-x-8" aria-label="Tabs">
          <Search.tab search_tab={@search_tab} tab={:motions} label={"Motions (#{length(@votings)})"} />
          <Search.tab
            search_tab={@search_tab}
            tab={:delegates}
            label={"Delegates (#{length(@authors)})"}
          />
          <Search.tab search_tab={@search_tab} tab={:quotes} label={"Quotes (#{length(@quotes)})"} />
          <Search.tab search_tab={@search_tab} tab={:halls} label={"Halls (#{length(@halls)})"} />
        </nav>
      </div>
    </div>
    <%= if @search_tab == :motions do %>
      <table>
        <%= for voting <- @votings do %>
          <tr>
            <td class="py-4 border-b border-gray-200">
              <a href={~p"/p/#{voting.slug}"}>{voting.title}</a>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    <%= if @search_tab == :delegates do %>
      <table>
        <%= for author <- @authors do %>
          <tr>
            <td class="py-4 border-b border-gray-200">
              <a href={author_path(author)}>{author.name || "x/#{author.twitter_username}"}</a>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    <%= if @search_tab == :halls do %>
      <table>
        <%= for hall <- @halls do %>
          <tr>
            <td class="py-4 border-b border-gray-200">
              <a href={~p"/halls/#{hall.name}"}>{hall.name}</a>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    <%= if @search_tab == :quotes do %>
      <table>
        <%= for quote <- @quotes do %>
          <tr>
            <td class="py-4 border-b border-gray-200">
              <div class="space-y-2">
                <div class="text-sm text-gray-600">
                  <a href={author_path(quote.author)} class="font-medium hover:underline">
                    {quote.author.name || "x/#{quote.author.twitter_username}"}
                  </a>
                </div>
                <div class="text-sm">
                  <a href={~p"/c/#{quote.id}"} class="hover:bg-gray-50 block p-2 -m-2 rounded">
                    {quote.content}
                  </a>
                </div>
                <%= if quote.source_url do %>
                  <div class="text-xs text-gray-500">
                    <a href={quote.source_url} target="_blank" class="hover:underline">
                      Source
                    </a>
                  </div>
                <% end %>
              </div>
            </td>
          </tr>
        <% end %>
      </table>
    <% end %>
    """
  end

  def tab(assigns) do
    ~H"""
    <div class="pt-1">
      <a
        href="#"
        phx-click="search-tab"
        phx-value-tab={@tab}
        class={[
          @search_tab == @tab &&
            "border-indigo-500 text-indigo-600 whitespace-nowrap border-b-2 py-2 px-1 text-sm font-medium",
          @search_tab != @tab &&
            "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 whitespace-nowrap border-b-2 py-2 px-1 text-sm font-medium"
        ]}
        aria-current="page"
      >
        {@label}
      </a>
    </div>
    """
  end
end
