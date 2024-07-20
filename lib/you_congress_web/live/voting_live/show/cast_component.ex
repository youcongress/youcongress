defmodule YouCongressWeb.VotingLive.Show.CastComponent do
  @moduledoc """
  Component for voting buttons
  """
  use Phoenix.Component

  attr :response, :string, required: true
  attr :current_user_vote, :map, required: true
  attr :button_id, :integer, required: true

  def button(assigns) do
    ~H"""
    <button
      id={@button_id}
      phx-click="vote"
      phx-value-response={@response}
      class={"rounded-lg bg-#{response_color(@response)}-500 px-4 py-2 text-xs font-semibold text-white shadow-sm ring-1 ring-inset ring-#{response_color(@response)}-300 hover:bg-#{response_color(@response)}-600"}
    >
      <%= if @current_user_vote && @current_user_vote.answer.response == @response,
        do: "✓ " %>
      <%= @response %>
      <%= if @current_user_vote && !@current_user_vote.direct && @current_user_vote.answer.response == @response do %>
        <span class="ml-1">
          via delegates
        </span>
      <% end %>
    </button>
    """
  end

  def response_color("Strongly agree"), do: "green"
  def response_color("Agree"), do: "lime"
  def response_color("Disagree"), do: "orange"
  def response_color("Strongly disagree"), do: "red"
  def response_color(_), do: "gray"
end
