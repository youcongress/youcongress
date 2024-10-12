defmodule YouCongressWeb.VotingLive.Show.CastComponent do
  @moduledoc """
  Component for voting buttons
  """
  use Phoenix.Component

  alias YouCongressWeb.VotingLive.Show.CastComponent

  attr :current_user_vote, :map, required: true
  attr :voting_id, :integer, required: true

  def buttons(assigns) do
    ~H"""
    <div class="pb-1">
      Cast your vote:
    </div>
    <div class="flex">
      <CastComponent.button
        response="Strongly agree"
        label1="Strongly"
        label2="Agree"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-strongly-agree"
      />
      <CastComponent.button
        response="Agree"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-agree"
      />
      <CastComponent.button
        response="Abstain"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-abstain"
      />
      <CastComponent.button
        response="N/A"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-na"
      />
      <CastComponent.button
        response="Disagree"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-disagree"
      />
      <CastComponent.button
        response="Strongly disagree"
        label1="Strongly"
        label2="Disagree"
        current_user_vote={@current_user_vote}
        voting_id={@voting_id}
        button_id="vote-strongly-disagree"
      />

      <%= if @current_user_vote do %>
        <%= if @current_user_vote.direct do %>
          <div class="pt-3 pl-1 hidden md:block text-xs">
            <button phx-click="delete-direct-vote" phx-value-voting_id={@voting_id} class="text-sm">
              Clear
            </button>
          </div>
        <% else %>
          <div class="pt-3 pl-1 hidden md:block text-xs">
            via delegates
          </div>
        <% end %>
      <% end %>
    </div>
    <%= if @current_user_vote && !@current_user_vote.direct do %>
      <div class="text-xs md:hidden">
        via delegates
      </div>
    <% end %>
    """
  end

  attr :response, :string, required: true
  attr :voting_id, :integer, required: true
  attr :label1, :string
  attr :label2, :string
  attr :current_user_vote, :map, required: true
  attr :button_id, :string, required: true

  def button(assigns) do
    ~H"""
    <div class="pr-1">
      <button
        id={@button_id}
        phx-click="vote"
        phx-value-response={@response}
        phx-value-voting_id={@voting_id}
        class={"rounded-lg bg-#{response_color(@response)}-500 h-10 flex md:p-4 flex-col justify-center items-center p-1 text-xs font-semibold text-white shadow-sm ring-1 ring-inset ring-#{response_color(@response)}-300 hover:bg-#{response_color(@response)}-600"}
      >
        <%= if assigns[:label1] && assigns[:label2] do %>
          <div>
            <%= if @current_user_vote && @current_user_vote.answer.response == @response,
              do: "✓ " %>
            <%= @label1 %>
          </div>
          <div>
            <%= @label2 %>
          </div>
        <% else %>
          <%= if @current_user_vote && @current_user_vote.answer.response == @response,
            do: "✓ " %>
          <div><%= @response %></div>
        <% end %>
      </button>
    </div>
    """
  end

  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true

  def results(assigns) do
    ~H"""
    <div class="pt-6 pb-1">
      Results (<%= @total_votes %>):
    </div>
    <div class="space-y-1">
      <div class="mb-2">
        <div class="w-full h-2 bar-bg rounded-full flex">
          <CastComponent.result
            response="Strongly agree"
            percentage={elem(@vote_frequencies["Strongly agree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Strongly agree"] && @vote_frequencies["Agree"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <CastComponent.result
            response="Agree"
            percentage={elem(@vote_frequencies["Agree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Strongly agree"] || @vote_frequencies["Agree"] do %>
            <div class="bg-white w-0.5"></div>
          <% end %>
          <CastComponent.result
            response="Abstain"
            percentage={elem(@vote_frequencies["Abstain"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["N/A"] && @vote_frequencies["Abstain"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <CastComponent.result
            response="N/A"
            percentage={elem(@vote_frequencies["N/A"] || {0, 0}, 1)}
          />
          <%= if (@vote_frequencies["Abstain"] || @vote_frequencies["N/A"]) && (@vote_frequencies["Disagree"] || @vote_frequencies["Strongly disagree"]) do %>
            <div class="bg-white w-0.5"></div>
          <% end %>
          <CastComponent.result
            response="Disagree"
            percentage={elem(@vote_frequencies["Disagree"] || {0, 0}, 1)}
          />
          <%= if @vote_frequencies["Disagree"] && @vote_frequencies["Strongly disagree"] do %>
            <div class="bg-black w-px"></div>
          <% end %>
          <CastComponent.result
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
