defmodule YouCongressWeb.StatementLive.ResultsComponent do
  @moduledoc """
  Component for voting results
  """
  use Phoenix.Component

  alias YouCongressWeb.StatementLive.ResultsComponent

  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true

  def horizontal_bar(assigns) do
    ~H"""
    <div class="pt-6 pb-1">
      Results ({@total_votes}):
    </div>
    <div class="space-y-1">
      <div class="mb-2">
        <div class="w-full h-2 bar-bg rounded-full flex">
          <ResultsComponent.result
            response="For"
            percentage={elem(@vote_frequencies[:for] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies[:for] && @vote_frequencies[:abstain] do %>
            <div class="bg-white w-px"></div>
          <% end %>
          <ResultsComponent.result
            response="Abstain"
            percentage={elem(@vote_frequencies[:abstain] || {0, 0}, 1)}
          />
          <%= if (@vote_frequencies[:abstain] || @vote_frequencies[:for]) && @vote_frequencies[:against] do %>
            <div class="bg-white w-px"></div>
          <% end %>
          <ResultsComponent.result
            response="Against"
            percentage={elem(@vote_frequencies[:against] || {0, 0}, 1)}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :response, :string, required: true
  attr :percentage, :integer, required: true
  attr :class, :string, default: ""

  def result(assigns) do
    ~H"""
    <div
      class={["bg-#{response_color(@response)}-500 h-2", @class]}
      style={"width: #{@percentage || 0}%;"}
    >
    </div>
    """
  end

  def response_color("For"), do: "green"
  def response_color(:for), do: "green"
  def response_color("Against"), do: "red"
  def response_color(:against), do: "red"
  def response_color("Abstain"), do: "blue"
  def response_color(:abstain), do: "blue"
  def response_color(_), do: "gray"
end
