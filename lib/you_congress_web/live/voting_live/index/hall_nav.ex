defmodule YouCongressWeb.VotingLive.Index.HallNav do
  use Phoenix.Component

  alias YouCongressWeb.VotingLive.Index.HallNav
  alias YouCongress.Tools.StringUtils

  attr :hall_name, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="border-b border-gray-200">
      <div class="hidden md:block">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <HallNav.tab url_hall_name={@hall_name} hall_name="ai" hall_link="/" hall_title="AI" />
          <%= if @hall_name not in ["ai", "climate", "space", "spain", "eu", "us", "law", "programming", "all"] do %>
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name={@hall_name}
              hall_link="/halls/#{@hall_name}"
              hall_title={StringUtils.titleize(@hall_name)}
            />
          <% end %>
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="climate"
            hall_link="/halls/climate"
            hall_title="Climate"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="space"
            hall_link="/halls/space"
            hall_title="Space"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="spain"
            hall_link="/halls/spain"
            hall_title="Spain"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="eu"
            hall_link="/halls/eu"
            hall_title="EU"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="us"
            hall_link="/halls/us"
            hall_title="US"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="law"
            hall_link="/halls/law"
            hall_title="Law"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="programming"
            hall_link="/halls/programming"
            hall_title="Programming"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="all"
            hall_link="/halls/all"
            hall_title="All"
          />
        </nav>
      </div>
      <div class="md:hidden">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <HallNav.tab url_hall_name={@hall_name} hall_name="ai" hall_link="/" hall_title="AI" />
          <%= if @hall_name not in ["ai", "climate", "all"] do %>
            <HallNav.tab
              url_hall_name={@hall_name}
              hall_name={@hall_name}
              hall_link="/halls/#{@hall_name}"
              hall_title={StringUtils.titleize(@hall_name)}
            />
          <% end %>
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="climate"
            hall_link="/halls/climate"
            hall_title="Climate"
          />
          <HallNav.tab
            url_hall_name={@hall_name}
            hall_name="all"
            hall_link="/halls/all"
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
          "border-indigo-500 text-indigo-600 whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium",
        @url_hall_name != @hall_name &&
          "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 whitespace-nowrap border-b-2 py-4 px-1 text-sm font-medium"
      ]}
      aria-current="page"
    >
      <%= @hall_title %>
    </a>
    """
  end
end
