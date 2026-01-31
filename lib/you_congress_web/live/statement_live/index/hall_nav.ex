defmodule YouCongressWeb.StatementLive.Index.HallNav do
  @moduledoc """
  Hall navigation - Reddit-like hall/subreddit selector.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.StatementLive.Index.HallNav
  alias YouCongress.Tools.StringUtils

  @featured_halls [
    {"ai", "AI"},
    {"ai-safety", "AI Safety"},
    {"ai-governance", "AI Governance"},
    {"existential-risk", "X-Risk"},
    {"cern-for-ai", "CERN for AI"},
    {"all", "All"}
  ]

  attr :hall_name, :string, required: true

  def render(assigns) do
    assigns = assign(assigns, :featured_halls, @featured_halls)

    ~H"""
    <div class="pb-2">
      <div class="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-hide">
        <span class="text-sm text-gray-500 shrink-0">y/</span>
        <div class="flex gap-2">
          <%= for {hall_slug, hall_title} <- @featured_halls do %>
            <HallNav.pill
              url_hall_name={@hall_name}
              hall_name={hall_slug}
              hall_link={hall_link(hall_slug)}
              hall_title={hall_title}
            />
          <% end %>
          <%= if @hall_name not in Enum.map(@featured_halls, &elem(&1, 0)) do %>
            <HallNav.pill
              url_hall_name={@hall_name}
              hall_name={@hall_name}
              hall_link={~p"/y/#{@hall_name}"}
              hall_title={StringUtils.titleize_hall(@hall_name)}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp hall_link("ai"), do: ~p"/"
  defp hall_link(hall_name), do: ~p"/y/#{hall_name}"

  attr :url_hall_name, :string, required: true
  attr :hall_link, :string, required: true
  attr :hall_name, :string, required: true
  attr :hall_title, :string, required: true

  @spec pill(map()) :: Phoenix.LiveView.Rendered.t()
  def pill(assigns) do
    ~H"""
    <a
      href={@hall_link}
      class={[
        "px-3 py-1.5 rounded-full text-sm font-medium whitespace-nowrap transition-colors",
        if(@url_hall_name == @hall_name,
          do: "bg-indigo-600 text-white",
          else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
        )
      ]}
    >
      {@hall_title}
    </a>
    """
  end

  # Keep the old tab function for backward compatibility if needed
  attr :url_hall_name, :string, required: true
  attr :hall_link, :string, required: true
  attr :hall_name, :string, required: true
  attr :hall_title, :string, required: true

  @spec tab(map()) :: Phoenix.LiveView.Rendered.t()
  def tab(assigns) do
    ~H"""
    <a
      href={@hall_link}
      class={[
        @url_hall_name == @hall_name &&
          "border-indigo-500 text-indigo-600 whitespace-nowrap border-b-2 py-2 px-1 text-sm font-medium",
        @url_hall_name != @hall_name &&
          "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 whitespace-nowrap border-b-2 py-2 px-1 text-sm font-medium"
      ]}
      aria-current="page"
    >
      {@hall_title}
    </a>
    """
  end
end
