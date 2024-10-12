defmodule YouCongressWeb.VotingLive.ResultsComponent do
  @moduledoc """
  Component for voting buttons
  """
  use Phoenix.Component

  alias YouCongressWeb.VotingLive.ResultsComponent

  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true

  def horizontal_bar(assigns) do
    ~H"""
    <div class="pt-6 pb-1">
      Results (<%= @total_votes %>):
    </div>
    <div class="space-y-1">
      <div class="mb-2">
        <div class="w-full h-2 bar-bg rounded-full flex">
          <ResultsComponent.result
            response="Strongly agree"
            percentage={elem(@vote_frequencies["Strongly agree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Strongly agree"] && @vote_frequencies["Agree"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <ResultsComponent.result
            response="Agree"
            percentage={elem(@vote_frequencies["Agree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Strongly agree"] || @vote_frequencies["Agree"] do %>
            <div class="bg-white w-0.5"></div>
          <% end %>
          <ResultsComponent.result
            response="Abstain"
            percentage={elem(@vote_frequencies["Abstain"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["N/A"] && @vote_frequencies["Abstain"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <ResultsComponent.result
            response="N/A"
            percentage={elem(@vote_frequencies["N/A"] || {0, 0}, 1)}
          />
          <%= if (@vote_frequencies["Abstain"] || @vote_frequencies["N/A"]) && (@vote_frequencies["Disagree"] || @vote_frequencies["Strongly disagree"]) do %>
            <div class="bg-white w-0.5"></div>
          <% end %>
          <ResultsComponent.result
            response="Disagree"
            percentage={elem(@vote_frequencies["Disagree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Disagree"] && @vote_frequencies["Strongly disagree"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <ResultsComponent.result
            response="Strongly disagree"
            percentage={elem(@vote_frequencies["Strongly disagree"] || {0, 0}, 1)}
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

  def response_color("Strongly agree"), do: "green"
  def response_color("Agree"), do: "lime"
  def response_color("Disagree"), do: "orange"
  def response_color("Strongly disagree"), do: "red"
  def response_color("Abstain"), do: "blue"
  def response_color(_), do: "gray"
end
