defmodule YouCongressWeb.StatementLive.SynthesisComponent do
  @moduledoc """
  Renders the AI-generated synthesis of a statement's sourced quotes.

  Only the headline, cluster titles/summaries, insights and conclusion come
  from the LLM. Quote excerpts and author names are rendered from the database
  via the cited opinion ids, and the tally comes from the votes table, so the
  card can never misquote anyone or misstate the numbers. Kept out of
  JSON-LD/meta (house rule: AI content never goes in structured data);
  data-nosnippet keeps it out of search snippets.
  """
  use Phoenix.Component
  use YouCongressWeb, :verified_routes

  alias YouCongress.Opinions.Opinion
  alias YouCongressWeb.SEO

  @excerpt_max_chars 280

  @sections [
    {"arguments_for", "Arguments for"},
    {"arguments_against", "Arguments against"},
    {"middle_ground", "Middle ground"}
  ]

  attr :statement, :map, required: true
  attr :synthesis, :map, required: true
  attr :show_synthesis, :boolean, required: true
  attr :synthesis_opinions, :map, required: true
  attr :can_regenerate, :boolean, default: false
  attr :synthesis_regenerating, :boolean, default: false

  def card(assigns) do
    {key_insights, source_observations} = split_insights(assigns.synthesis["insights"])

    assigns =
      assigns
      |> assign(:sections, @sections)
      |> assign(:key_insights, key_insights)
      |> assign(:source_observations, source_observations)

    ~H"""
    <div class="mb-6 rounded-lg border border-gray-200 bg-gray-50 p-4" data-nosnippet>
      <button
        type="button"
        phx-click="toggle-synthesis"
        aria-expanded={to_string(@show_synthesis)}
        aria-controls="synthesis-body"
        class="w-full text-left"
      >
        <%!-- Only phrasing content here: a button may not contain div/p. --%>
        <span class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold uppercase tracking-wide text-gray-500">
            AI synthesis
          </span>
          <span class="shrink-0 text-xs text-gray-500 underline">
            {if @show_synthesis, do: "Hide", else: "Show more"}
          </span>
        </span>
        <span class="mt-1 block font-semibold">{@synthesis["headline"]}</span>
        <span :if={!@show_synthesis} class="mt-2 inline-block text-sm text-gray-600 underline">
          Show insights and arguments
        </span>
      </button>

      <%!-- Always in the DOM (crawlable); the toggle only flips visibility. --%>
      <div id="synthesis-body" class={["mt-4 space-y-6", !@show_synthesis && "hidden"]}>
        <section :if={@key_insights != []}>
          <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500">Key insights</h2>
          <ul class="mt-2 list-inside list-disc space-y-1 text-sm text-gray-700">
            <li :for={insight <- @key_insights}>{insight}</li>
          </ul>
        </section>

        <section :for={{key, label} <- @sections} :if={@synthesis[key] not in [nil, []]}>
          <h2 class={section_class(key)}>{label}</h2>
          <div :for={cluster <- @synthesis[key]} class="mt-3">
            <h3 class="text-sm font-semibold">{cluster["title"]}</h3>
            <p class="text-sm text-gray-700">{cluster["summary"]}</p>
            <ul class="mt-2 space-y-2">
              <li
                :for={opinion <- resolve(cluster["opinion_ids"], @synthesis_opinions)}
                class="text-sm"
              >
                <blockquote
                  cite={opinion.source_url}
                  class="border-l-2 border-gray-300 pl-3 italic text-gray-600"
                >
                  {excerpt(opinion.content)}
                </blockquote>
                <div class="mt-1 text-xs text-gray-500">
                  <.link
                    :if={opinion.author}
                    navigate={SEO.author_path(opinion.author)}
                    class="font-semibold underline"
                  >
                    {opinion.author.name}
                  </.link>
                  <span :if={Opinion.display_date(opinion)}>· {Opinion.display_date(opinion)}</span>
                  · <.link navigate={~p"/c/#{opinion.id}"} class="underline">full quote</.link>
                </div>
              </li>
            </ul>
          </div>
        </section>

        <p class="text-sm text-gray-700">{@synthesis["conclusion"]}</p>

        <section :if={@source_observations != []}>
          <h2 class="text-sm font-bold uppercase tracking-wide text-gray-500">Source diversity</h2>
          <ul class="mt-2 list-inside list-disc space-y-1 text-sm text-gray-700">
            <li :for={observation <- @source_observations}>{observation}</li>
          </ul>
        </section>

        <footer class="flex items-center justify-between gap-2 border-t border-gray-200 pt-2 text-xs text-gray-500">
          <span>
            AI-generated from the quotes on this page{generated_on(@statement)}. It may contain mistakes.
          </span>
          <button
            :if={@can_regenerate}
            type="button"
            phx-click="regenerate-synthesis"
            disabled={@synthesis_regenerating}
            class="shrink-0 underline disabled:opacity-50"
          >
            {if @synthesis_regenerating, do: "Regenerating…", else: "Regenerate"}
          </button>
        </footer>
      </div>
    </div>
    """
  end

  defp section_class("arguments_for"),
    do: "text-sm font-bold uppercase tracking-wide text-green-800"

  defp section_class("arguments_against"),
    do: "text-sm font-bold uppercase tracking-wide text-red-700"

  defp section_class(_), do: "text-sm font-bold uppercase tracking-wide text-blue-800"

  # Older syntheses store substantive insights and observations about the
  # quoted contributors in one list. Keep both kinds of content, but separate
  # clear source-diversity observations so the debate itself stays up front.
  defp split_insights(insights) do
    insights
    |> List.wrap()
    |> Enum.split_with(&(not source_diversity_observation?(&1)))
  end

  defp source_diversity_observation?(insight) when is_binary(insight) do
    insight = String.downcase(insight)

    source_focused? =
      Regex.match?(~r/\b(quotes?|contributors?|authors?|speakers?|voices)\b/, insight) or
        Regex.match?(~r/\bsupport(?:ers)? and opposition\b/, insight)

    background_focused? =
      Regex.match?(
        ~r/\b(backgrounds?|professions?|roles?|institutions?|fields?|sectors?)\b/,
        insight
      )

    diversity_focused? =
      Regex.match?(
        ~r/\b(varied|diverse|diversity|range|mix|span|spans|include|includes|across)\b/,
        insight
      ) or
        String.contains?(insight, "come from")

    source_focused? and background_focused? and diversity_focused?
  end

  defp source_diversity_observation?(_), do: false

  defp resolve(ids, opinions_by_id) do
    ids
    |> List.wrap()
    |> Enum.map(&Map.get(opinions_by_id, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp excerpt(content) when is_binary(content) do
    if String.length(content) <= @excerpt_max_chars do
      content
    else
      String.slice(content, 0, @excerpt_max_chars) <> "…"
    end
  end

  defp excerpt(_), do: ""

  defp generated_on(%{synthesis_generated_at: %DateTime{} = generated_at}) do
    " on " <> Calendar.strftime(generated_at, "%b %d, %Y")
  end

  defp generated_on(_), do: ""
end
