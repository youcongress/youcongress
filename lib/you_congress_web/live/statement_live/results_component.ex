defmodule YouCongressWeb.StatementLive.ResultsComponent do
  @moduledoc """
  Component for voting results
  """
  use Phoenix.Component

  alias YouCongressWeb.StatementLive.ResultsComponent

  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true
  attr :country_vote_frequencies, :list, default: []

  def horizontal_bar(assigns) do
    ~H"""
    <div class="pt-6 pb-1 space-y-4">
      <div class="text-sm font-semibold">
        Results ({vote_count_label(@total_votes)}):
      </div>

      <ResultsComponent.result_row
        label="Total"
        total_votes={@total_votes}
        vote_frequencies={@vote_frequencies}
        emphasis={true}
      />

      <details :if={@country_vote_frequencies != []} class="space-y-3">
        <summary class="cursor-pointer select-none text-xs font-semibold uppercase tracking-wide text-gray-500 hover:text-gray-700">
          By country
        </summary>
        <div class="space-y-3 pt-2">
          <ResultsComponent.result_row
            :for={country <- @country_vote_frequencies}
            label={country.country_name}
            total_votes={country.total_votes}
            vote_frequencies={country.vote_frequencies}
          />
        </div>
      </details>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true
  attr :emphasis, :boolean, default: false
  attr :class, :string, default: ""

  def result_row(assigns) do
    assigns = assign(assigns, :stats, vote_stats(assigns.vote_frequencies))

    ~H"""
    <div class={["space-y-1", @class]}>
      <div class="flex flex-col gap-1 md:flex-row md:items-baseline md:justify-between md:gap-3">
        <div class={
          if @emphasis, do: "text-sm font-semibold", else: "text-xs font-medium text-gray-700"
        }>
          {@label}
          <span class="font-normal text-gray-500">({vote_count_label(@total_votes)})</span>
        </div>
        <div class="flex flex-wrap gap-x-3 gap-y-1 text-xs">
          <span :for={stat <- @stats} class={response_text_color(stat.response)}>
            {stat.label} {stat.count} ({stat.percentage}%)
          </span>
        </div>
      </div>
      <ResultsComponent.bar
        vote_frequencies={@vote_frequencies}
        height_class={if @emphasis, do: "h-3", else: "h-2"}
      />
    </div>
    """
  end

  attr :vote_frequencies, :map, required: true
  attr :height_class, :string, default: "h-2"

  def bar(assigns) do
    ~H"""
    <div class={["w-full bar-bg rounded-full flex overflow-hidden", @height_class]}>
      <ResultsComponent.result response="For" percentage={percentage(@vote_frequencies, :for)} />
      <%= if has_percentage?(@vote_frequencies, :for) && has_percentage?(@vote_frequencies, :abstain) do %>
        <div class="bg-white w-px"></div>
      <% end %>
      <ResultsComponent.result
        response="Abstain"
        percentage={percentage(@vote_frequencies, :abstain)}
      />
      <%= if (has_percentage?(@vote_frequencies, :for) || has_percentage?(@vote_frequencies, :abstain)) &&
              has_percentage?(@vote_frequencies, :against) do %>
        <div class="bg-white w-px"></div>
      <% end %>
      <ResultsComponent.result
        response="Against"
        percentage={percentage(@vote_frequencies, :against)}
      />
    </div>
    """
  end

  attr :response, :string, required: true
  attr :percentage, :integer, required: true
  attr :class, :string, default: ""

  def result(assigns) do
    ~H"""
    <div
      class={["bg-#{response_color(@response)}-500 h-full", @class]}
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

  def response_text_color(:for), do: "text-green-800"
  def response_text_color(:against), do: "text-red-800"
  def response_text_color(:abstain), do: "text-blue-800"
  def response_text_color(_), do: "text-gray-800"

  defp vote_stats(vote_frequencies) do
    Enum.map([:for, :abstain, :against], fn response ->
      {count, percentage} = Map.get(vote_frequencies, response, {0, 0})

      %{
        response: response,
        label: response_label(response),
        count: count,
        percentage: percentage
      }
    end)
  end

  defp response_label(:for), do: "For"
  defp response_label(:against), do: "Against"
  defp response_label(:abstain), do: "Abstain"

  defp percentage(vote_frequencies, response) do
    vote_frequencies
    |> Map.get(response, {0, 0})
    |> elem(1)
  end

  defp has_percentage?(vote_frequencies, response) do
    percentage(vote_frequencies, response) > 0
  end

  defp vote_count_label(1), do: "1 vote"
  defp vote_count_label(count), do: "#{count} votes"
end
