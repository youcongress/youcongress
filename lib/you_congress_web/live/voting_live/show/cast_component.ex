defmodule YouCongressWeb.VotingLive.Show.CastComponent do
  @moduledoc """
  Component for voting buttons
  """
  use Phoenix.Component

  attr :response, :string, required: true
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

  def response_color("Strongly agree"), do: "green"
  def response_color("Agree"), do: "lime"
  def response_color("Disagree"), do: "orange"
  def response_color("Strongly disagree"), do: "red"
  def response_color("Abstain"), do: "blue"
  def response_color(_), do: "gray"
end
