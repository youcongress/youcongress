defmodule YouCongressWeb.StatementLive.Index.HallHero do
  @moduledoc """
  Topic-hub intro for hall pages: H1, description, stats and top-author
  links, plus CollectionPage JSON-LD — so /h/:hall pages rank for
  "expert opinions on {topic}" queries and AI assistants can cite them.
  """
  use Phoenix.Component
  use YouCongressWeb, :verified_routes

  import YouCongressWeb.SEOComponents

  alias YouCongress.Tools.StringUtils
  alias YouCongressWeb.SEO

  attr :hall_name, :string, required: true
  attr :stats, :map, default: nil

  def render(%{stats: nil} = assigns) do
    ~H"""
    <div class="text-center pt-2 pb-4">
      <h1 class="text-2xl font-bold leading-8 text-gray-600">
        Expert opinions on {StringUtils.titleize_hall(@hall_name)}
      </h1>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="text-center pt-2 pb-4">
      <.json_ld data={collection_page(@hall_name, @stats)} />
      <div class="leading-8 text-gray-600">
        <h1 class="text-2xl font-bold">
          Expert opinions on {StringUtils.titleize_hall(@hall_name)}
        </h1>
        <p class="text-lg">{intro(@hall_name, @stats)}</p>
        <p class="text-sm text-gray-500">
          {@stats.quote_count} sourced {plural(@stats.quote_count, "quote")} · {@stats.statement_count} {plural(
            @stats.statement_count,
            "statement"
          )}{vote_split(@stats.vote_totals)}
        </p>
        <p
          :if={@stats.top_authors != []}
          class="pt-1 text-sm flex flex-wrap gap-x-3 gap-y-1 justify-center"
        >
          <span class="text-gray-500">Featuring:</span>
          <.link
            :for={author <- @stats.top_authors}
            href={SEO.author_path(author)}
            class="hover:text-indigo-600 hover:underline"
          >
            {author.name}
          </.link>
        </p>
      </div>
    </div>
    """
  end

  defp collection_page(hall_name, stats) do
    statement_urls = Enum.map(stats.statements, &url(~p"/p/#{&1.slug}"))
    SEO.collection_page(hall_name, intro(hall_name, stats), statement_urls)
  end

  defp intro(hall_name, stats) do
    stats.hall.description ||
      "Quotes, votes and policy statements on #{StringUtils.titleize_hall(hall_name)} " <>
        "from AI researchers, executives and policymakers."
  end

  defp vote_split(vote_totals) do
    total = vote_totals |> Map.values() |> Enum.sum()

    if total > 0 do
      for_pct = round(Map.get(vote_totals, :for, 0) / total * 100)
      against_pct = round(Map.get(vote_totals, :against, 0) / total * 100)
      " · #{for_pct}% for / #{against_pct}% against overall"
    end
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end
