defmodule YouCongressWeb.StatementLive.Index.Search do
  @moduledoc """
  Search statements (policy proposals and claims), delegates, halls, and quotes
  """
  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.StatementLive.Index.Search

  defdelegate author_path(path), to: YouCongressWeb.AuthorLive.Show, as: :author_path

  attr :search_tab, :atom, required: true
  attr :search_term, :string, required: true
  attr :statements, :map, required: true
  attr :authors, :map, required: true
  attr :halls, :map, required: true
  attr :quotes, :map, required: true
  attr :search_has_more, :map, required: true

  def render(assigns) do
    parsed_terms = YouCongress.SearchParser.parse(assigns.search_term)

    assigns =
      assigns
      |> assign(:parsed_terms, parsed_terms)
      |> assign(:quotes_label, results_label(assigns.quotes, assigns.search_has_more[:quotes]))
      |> assign(
        :authors_label,
        results_label(assigns.authors, assigns.search_has_more[:delegates])
      )
      |> assign(
        :statements_label,
        results_label(assigns.statements, assigns.search_has_more[:statements])
      )
      |> assign(:halls_label, results_label(assigns.halls, assigns.search_has_more[:halls]))
      |> assign(:active_tab_has_more, Map.get(assigns.search_has_more, assigns.search_tab, false))
      |> assign(:active_results_count, active_results_count(assigns))

    ~H"""
    <div id="search-results" class="pt-4">
      <div class="border-b border-gray-200">
        <div class="pb-2">
          <nav class="-mb-px grid grid-cols-2 md:flex md:space-x-8" aria-label="Tabs">
            <Search.tab search_tab={@search_tab} tab={:quotes} label={"Quotes (#{@quotes_label})"} />
            <Search.tab
              search_tab={@search_tab}
              tab={:delegates}
              label={"Delegates (#{@authors_label})"}
            />
            <Search.tab
              search_tab={@search_tab}
              tab={:statements}
              label={"Policies & claims (#{@statements_label})"}
            />
            <Search.tab search_tab={@search_tab} tab={:halls} label={"Halls (#{@halls_label})"} />
          </nav>
        </div>
      </div>
      <%= if @search_tab == :statements do %>
        <table class="w-full">
          <%= for statement <- @statements do %>
            <tr>
              <td class="py-4 border-b border-gray-200">
                <a href={~p"/p/#{statement.slug}"} phx-no-format><.highlight text={statement.title} terms={@parsed_terms} /></a>
              </td>
            </tr>
          <% end %>
        </table>
      <% end %>
      <%= if @search_tab == :delegates do %>
        <table class="w-full">
          <%= for author <- @authors do %>
            <tr>
              <td class="py-4 border-b border-gray-200">
                <% bio = author_bio(author) %>
                <div class="flex flex-col gap-1 text-sm sm:flex-row sm:items-start sm:justify-between">
                  <a
                    href={author_path(author)}
                    class="font-medium text-gray-900 hover:underline"
                    phx-no-format
                  ><.highlight text={author.name || "x/#{author.twitter_username}"} terms={@parsed_terms}/></a>
                  <p :if={bio} class="text-xs text-gray-500 sm:text-right sm:text-sm sm:pl-6">
                    {bio}
                  </p>
                </div>
              </td>
            </tr>
          <% end %>
        </table>
      <% end %>
      <%= if @search_tab == :halls do %>
        <table class="w-full">
          <%= for hall <- @halls do %>
            <tr>
              <td class="py-4 border-b border-gray-200">
                <a href={~p"/h/#{hall.name}"} phx-no-format>h/<.highlight text={hall.name} terms={@parsed_terms}/></a>
              </td>
            </tr>
          <% end %>
        </table>
      <% end %>
      <%= if @search_tab == :quotes do %>
        <table class="w-full">
          <%= for quote <- @quotes do %>
            <tr>
              <td class="py-4 border-b border-gray-200">
                <div class="space-y-2">
                  <div class="text-sm text-gray-600">
                    <% bio = author_bio(quote.author) %>
                    <div class="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between">
                      <a
                        href={author_path(quote.author)}
                        class="font-medium hover:underline"
                        phx-no-format
                      ><.highlight text={quote.author.name || "x/#{quote.author.twitter_username}"} terms={@parsed_terms}/></a>
                      <p :if={bio} class="text-xs text-gray-500 sm:text-right sm:text-sm sm:pl-6">
                        {bio}
                      </p>
                    </div>
                  </div>
                  <div class="text-sm">
                    <a
                      href={~p"/c/#{quote.id}"}
                      class="hover:bg-gray-50 block p-2 -m-2 rounded"
                      phx-no-format
                    ><.highlight text={quote.content} terms={@parsed_terms}/></a>
                  </div>
                  <%= if quote.source_url do %>
                    <div class="text-xs text-gray-500 flex items-center gap-2">
                      <a href={quote.source_url} target="_blank" class="hover:underline">
                        Source
                      </a>
                      <span :if={quote.year} class="text-gray-400">{quote.year}</span>
                    </div>
                  <% end %>
                </div>
              </td>
            </tr>
          <% end %>
        </table>
      <% end %>
      <div
        :if={@active_tab_has_more}
        id="search-results-sentinel"
        phx-hook="InfiniteSearchResults"
        data-has-more={to_string(@active_tab_has_more)}
        data-result-count={@active_results_count}
        class="flex justify-center py-4 text-sm text-gray-500"
      >
        Loading more results...
      </div>
    </div>
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

  attr :text, :string, required: true
  attr :term, :string, default: nil
  attr :terms, :list, default: nil

  def highlight(assigns) do
    terms =
      (assigns.terms || [assigns.term])
      |> Enum.reject(&(&1 == nil or &1 == ""))

    if terms == [] do
      ~H"{@text}"
    else
      pattern = Enum.map_join(terms, "|", &Regex.escape/1)
      regex = Regex.compile!(pattern, "i")
      parts = Regex.split(regex, assigns.text, include_captures: true)
      assigns = assign(assigns, parts: parts, regex: regex)

      ~H"""
      <span phx-no-format><%= for part <- @parts do %><%= if String.match?(part, @regex) do %><b>{part}</b><% else %>{part}<% end %><% end %></span>
      """
    end
  end

  defp author_bio(%{bio: bio, description: description}) do
    cond do
      present?(bio) -> bio
      present?(description) -> description
      true -> nil
    end
  end

  defp author_bio(_), do: nil

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp results_label(results, true), do: "#{length(results)}+"
  defp results_label(results, false), do: length(results)

  defp active_results_count(%{search_tab: :quotes, quotes: quotes}), do: length(quotes)
  defp active_results_count(%{search_tab: :delegates, authors: authors}), do: length(authors)

  defp active_results_count(%{search_tab: :statements, statements: statements}),
    do: length(statements)

  defp active_results_count(%{search_tab: :halls, halls: halls}), do: length(halls)
  defp active_results_count(_), do: 0
end
