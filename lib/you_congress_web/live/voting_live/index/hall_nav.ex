defmodule YouCongressWeb.VotingLive.Index.HallNav do
  @moduledoc """
  Hall navigation.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: YouCongressWeb.Endpoint, router: YouCongressWeb.Router

  alias YouCongressWeb.VotingLive.Index.HallNav
  alias YouCongress.Tools.StringUtils

  attr :hall_name, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="border-b border-gray-200">
      <div class="pb-2">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <div class="pt-1 space-x-8">
            <HallNav.tab url_hall_name={@hall_name} hall_name="ai" hall_link={~p"/"} hall_title="AI" />
            <HallNav.tab url_hall_name={@hall_name} hall_name="public-interest-ai" hall_link={~p"/halls/public-interest-ai"} hall_title="Public interest AI" />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="future-of-work"
              hall_link={~p"/halls/future-of-work"}
              hall_title="Future of work"
            />
          </div>
          <div class="hidden md:block pt-1 space-x-8">
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="ai-innovation-and-culture"
              hall_link={~p"/halls/ai-innovation-and-culture"}
              hall_title="AI Innovation and culture"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="trust-in-ai"
              hall_link={~p"/halls/trust-in-ai"}
              hall_title="Trust in AI"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="global-ai-governance"
              hall_link={~p"/halls/global-ai-governance"}
              hall_title="Global AI governance"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="all"
              hall_link={~p"/halls/all"}
              hall_title="All"
            />
          </div>
        </nav>
      </div>
      <div class="-mb-px flex space-x-8 md:hidden">
        <%= if @hall_name not in ["ai", "climate", "space", "eu", "us", "law", "health", "all"] do %>
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name={@hall_name}
            hall_link={~p"/halls/#{@hall_name}"}
            hall_title={StringUtils.titleize_hall(@hall_name)}
          />
        <% else %>
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="spain"
            hall_link={~p"/halls/spain"}
            hall_title="AI innovation and culture"
          />
        <% end %>
        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="law"
          hall_link={~p"/halls/law"}
          hall_title="Trust in AI"
        />
        </div>
        <div class="-mb-px flex space-x-8 md:hidden">

        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="us"
          hall_link={~p"/halls/us"}
          hall_title="Global AI governance"
        />
        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="eu"
          hall_link={~p"/halls/eu"}
          hall_title="All"
        />
      </div>
    </div>
    """
  end

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
      <%= @hall_title %>
    </a>
    """
  end
end
