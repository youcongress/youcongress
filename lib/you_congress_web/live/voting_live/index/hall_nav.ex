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
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="climate"
              hall_link={~p"/halls/climate"}
              hall_title="Climate"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="health"
              hall_link={~p"/halls/health"}
              hall_title="Health"
            />
          </div>
          <div class="hidden md:block pt-1 space-x-8">
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="law"
              hall_link={~p"/halls/law"}
              hall_title="Law"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="us"
              hall_link={~p"/halls/us"}
              hall_title="US"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="eu"
              hall_link={~p"/halls/eu"}
              hall_title="EU"
            />
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name="spain"
              hall_link={~p"/halls/spain"}
              hall_title="Spain"
            />
          </div>
          <div class="pt-1 space-x-8">
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
            hall_title="Spain"
          />
        <% end %>
        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="law"
          hall_link={~p"/halls/law"}
          hall_title="Law"
        />
        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="us"
          hall_link={~p"/halls/us"}
          hall_title="US"
        />
        <HallNav.tab
          url_hall_name={@hall_name}
          hall_name="eu"
          hall_link={~p"/halls/eu"}
          hall_title="EU"
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
