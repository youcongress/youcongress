defmodule YouCongressWeb.StatementLive.ResultsComponent do
  @moduledoc """
  Component for voting results
  """
  use Phoenix.Component

  alias YouCongressWeb.StatementLive.ResultsComponent

  @responses [:for, :abstain, :against]

  attr :id, :string, default: nil
  attr :statement_id, :integer, default: nil
  attr :total_votes, :integer, required: true
  attr :vote_frequencies, :map, required: true
  attr :country_vote_frequencies, :list, default: nil
  attr :show_country_results, :boolean, default: false
  attr :country_results_filters, :map, default: %{}
  attr :country_results_target, :any, default: nil
  attr :year_vote_frequencies, :list, default: nil
  attr :show_year_results, :boolean, default: false
  attr :year_results_filters, :map, default: %{}
  attr :year_results_target, :any, default: nil

  def horizontal_bar(assigns) do
    assigns = assign_display_results(assigns)

    ~H"""
    <div class="pt-6 pb-1 space-y-4">
      <div class="text-sm font-semibold">
        Results ({vote_count_label(@display_total_votes)}):
      </div>

      <ResultsComponent.result_row
        label="Total"
        total_votes={@display_total_votes}
        vote_frequencies={@display_vote_frequencies}
        emphasis={true}
      />

      <div :if={@statement_id} class="space-y-3">
        <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-gray-500">
          <button
            id={if @id, do: "#{@id}-by-country"}
            type="button"
            phx-click="toggle-country-results"
            phx-value-statement_id={@statement_id}
            phx-target={@country_results_target}
            class="uppercase tracking-wide hover:text-gray-700"
          >
            By country
          </button>
          <span class="text-gray-300">·</span>
          <button
            id={if @id, do: "#{@id}-by-year"}
            type="button"
            phx-click="toggle-year-results"
            phx-value-statement_id={@statement_id}
            phx-target={@year_results_target}
            class="uppercase tracking-wide hover:text-gray-700"
          >
            By year
          </button>
        </div>
        <div :if={@show_country_results} class="grid gap-3 text-xs md:grid-cols-2">
          <ResultsComponent.country_filter_group
            title="Vote type"
            filters={@country_results_filters}
            statement_id={@statement_id}
            target={@country_results_target}
            options={[
              {:direct, "Direct votes"},
              {:delegated, "Delegated votes"}
            ]}
          />
          <ResultsComponent.country_filter_group
            title="Source"
            filters={@country_results_filters}
            statement_id={@statement_id}
            target={@country_results_target}
            options={[
              {:quotes, "Quotes"},
              {:email_verified, "Users verified by email"},
              {:phone_verified, "Users verified by phone"}
            ]}
          />
        </div>
        <div
          :if={@show_country_results && is_nil(@country_vote_frequencies)}
          class="text-xs text-gray-500"
        >
          Loading country results...
        </div>
        <div
          :if={@show_country_results && @country_vote_frequencies == []}
          class="text-xs text-gray-500"
        >
          No country results yet.
        </div>
        <div
          :if={
            @show_country_results && is_list(@country_vote_frequencies) &&
              @country_vote_frequencies != []
          }
          class="space-y-3"
        >
          <ResultsComponent.result_row
            :for={country <- @country_vote_frequencies}
            label={country.country_name}
            total_votes={country.total_votes}
            vote_frequencies={country.vote_frequencies}
          />
        </div>

        <div :if={@show_year_results} class="grid gap-3 text-xs md:grid-cols-2">
          <ResultsComponent.country_filter_group
            title="Vote type"
            filters={@year_results_filters}
            statement_id={@statement_id}
            target={@year_results_target}
            filter_event="toggle-year-results-filter"
            options={[
              {:direct, "Direct votes"},
              {:delegated, "Delegated votes"}
            ]}
          />
          <ResultsComponent.country_filter_group
            title="Source"
            filters={@year_results_filters}
            statement_id={@statement_id}
            target={@year_results_target}
            filter_event="toggle-year-results-filter"
            options={[
              {:quotes, "Quotes"},
              {:email_verified, "Users verified by email"},
              {:phone_verified, "Users verified by phone"}
            ]}
          />
        </div>
        <div
          :if={@show_year_results && is_nil(@year_vote_frequencies)}
          class="text-xs text-gray-500"
        >
          Loading year results...
        </div>
        <div
          :if={@show_year_results && @year_vote_frequencies == []}
          class="text-xs text-gray-500"
        >
          No dated quotes yet.
        </div>
        <div
          :if={
            @show_year_results && is_list(@year_vote_frequencies) &&
              @year_vote_frequencies != []
          }
          class="space-y-3"
        >
          <ResultsComponent.result_row
            :for={year <- @year_vote_frequencies}
            label={to_string(year.year)}
            total_votes={year.total_votes}
            vote_frequencies={year.vote_frequencies}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :filters, :map, required: true
  attr :statement_id, :integer, required: true
  attr :target, :any, default: nil
  attr :options, :list, required: true
  attr :filter_event, :string, default: "toggle-country-results-filter"

  def country_filter_group(assigns) do
    ~H"""
    <fieldset class="space-y-1">
      <legend class="font-semibold text-gray-600">{@title}</legend>
      <label :for={{filter, label} <- @options} class="flex items-center gap-2 text-gray-700">
        <input
          type="checkbox"
          checked={Map.get(@filters, filter, false)}
          phx-click={@filter_event}
          phx-value-filter={filter}
          phx-value-statement_id={@statement_id}
          phx-target={@target}
          class="h-3.5 w-3.5 rounded border-gray-300 text-zinc-900"
        />
        <span>{label}</span>
      </label>
    </fieldset>
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
    Enum.map(@responses, fn response ->
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

  defp assign_display_results(
         %{show_country_results: true, country_vote_frequencies: country_vote_frequencies} =
           assigns
       )
       when is_list(country_vote_frequencies) do
    counts =
      Map.new(@responses, fn response ->
        count =
          Enum.sum_by(country_vote_frequencies, fn country ->
            country.vote_frequencies
            |> Map.get(response, {0, 0})
            |> elem(0)
          end)

        {response, count}
      end)

    assigns
    |> assign(:display_total_votes, Enum.sum(Map.values(counts)))
    |> assign(:display_vote_frequencies, frequencies(counts))
  end

  defp assign_display_results(assigns) do
    assigns
    |> assign(:display_total_votes, assigns.total_votes)
    |> assign(:display_vote_frequencies, assigns.vote_frequencies)
  end

  defp frequencies(counts) do
    total = Enum.sum(Map.values(counts))

    Map.new(@responses, fn response ->
      count = Map.get(counts, response, 0)
      {response, {count, frequency_percentage(count, total)}}
    end)
  end

  defp frequency_percentage(_count, 0), do: 0
  defp frequency_percentage(count, total), do: round(count * 100 / total)

  defp vote_count_label(1), do: "1 vote"
  defp vote_count_label(count), do: "#{count} votes"
end
