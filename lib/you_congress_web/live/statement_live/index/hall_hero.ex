defmodule YouCongressWeb.StatementLive.Index.HallHero do
  @moduledoc """
  Topic-hub intro for hall pages: H1, description, stats and top-author
  links, plus CollectionPage JSON-LD, so public positions remain discoverable
  without implying that the collected sources form a representative expert poll.
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
        Sourced positions on {StringUtils.titleize_hall(@hall_name)}
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
          Sourced positions on {StringUtils.titleize_hall(@hall_name)}
        </h1>
        <p class="text-lg">{intro(@hall_name, @stats)}</p>
        <.summary stats={@stats} />
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true

  def summary(%{stats: nil} = assigns) do
    ~H"""
    """
  end

  def summary(assigns) do
    ~H"""
    <p id="site-intro-stats" class="text-sm text-gray-500">
      {@stats.quote_count} sourced {plural(@stats.quote_count, "quote")} · {@stats.statement_count} policy proposals and claims
    </p>
    <p
      :if={@stats.top_authors != []}
      id="site-intro-featured-authors"
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
    """
  end

  defp collection_page(hall_name, stats) do
    statement_urls = Enum.map(stats.statements, &url(~p"/p/#{&1.slug}"))
    SEO.collection_page(hall_name, intro(hall_name, stats), statement_urls)
  end

  defp intro(hall_name, stats) do
    stats.hall.description ||
      "Traceable public statements, claims, policy proposals and stance annotations on " <>
        "#{StringUtils.titleize_hall(hall_name)}. Record counts are not polls or truth scores."
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"
end
