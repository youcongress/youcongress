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
          </div>
          <div class="hidden md:block pt-1 space-x-8">
            <%= if @hall_name not in ["ai", "global-ai-governance", "future-of-work", "climate-change", "housing", "us", "eu", "all"] do %>
              <HallNav.tab
                url_hall_name={@hall_name}
                hall_name={@hall_name}
                hall_link={~p"/halls/#{@hall_name}"}
                hall_title={StringUtils.titleize_hall(@hall_name)}
              />
            <% else %>
              <HallNav.tab
                url_hall_name={@hall_name}
                hall_name="global-ai-governance"
                hall_link={~p"/halls/global-ai-governance"}
                hall_title="AI governance"
              />
            <% end %>
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="future-of-work"
              hall_link={~p"/halls/future-of-work"}
              hall_title="Future of Work"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="climate-change"
              hall_link={~p"/halls/climate-change"}
              hall_title="Climate Change"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="housing"
              hall_link={~p"/halls/housing"}
              hall_title="Housing"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="eu"
              hall_link={~p"/halls/eu"}
              hall_title="European Union"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="us"
              hall_link={~p"/halls/us"}
              hall_title="United States"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="all"
              hall_link={~p"/halls/all"}
              hall_title="All"
            />
          </div>
          <div class="space-x-8 md:hidden pt-1">
            <%= if @hall_name not in ["ai", "public-interest-ai", "future-of-work", "ai-innovation-and-culture", "trust-in-ai", "global-ai-governance", "all"] do %>
              <HallNav.tab
                url_hall_name={@hall_name}
                hall_name={@hall_name}
                hall_link={~p"/halls/#{@hall_name}"}
                hall_title={StringUtils.titleize_hall(@hall_name)}
              />
            <% else %>
              <HallNav.tab
                url_hall_name={@hall_name}
                hall_name="global-ai-governance"
                hall_link={~p"/halls/global-ai-governance"}
                hall_title="AI governance"
              />
            <% end %>
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="future-of-work"
              hall_link={~p"/halls/future-of-work"}
              hall_title="Future of Work"
            />
          </div>
        </nav>
        <nav class="flex space-x-4 md:hidden pt-4">
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="climate-change"
              hall_link={~p"/halls/climate-change"}
              hall_title="Climate Change"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="housing"
              hall_link={~p"/halls/housing"}
              hall_title="Housing"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="eu"
              hall_link={~p"/halls/eu"}
              hall_title="EU"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="us"
              hall_link={~p"/halls/us"}
              hall_title="US"
            />

          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="all"
            hall_link={~p"/halls/all"}
            hall_title="All"
          />
        </nav>
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
