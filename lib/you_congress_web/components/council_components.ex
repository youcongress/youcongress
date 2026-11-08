defmodule YouCongressWeb.CouncilComponents do
  @moduledoc "Shared Council, Trust 30, and vote explanation presentation."
  use YouCongressWeb, :html

  attr :person, :map, required: true
  attr :large, :boolean, default: false

  def avatar(assigns) do
    ~H"""
    <span class={["yc-avatar", @large && "big"]} aria-hidden="true">
      {initials(@person.name)}
    </span>
    """
  end

  attr :person, :map, required: true
  attr :subtitle, :string, default: nil

  def person(assigns) do
    ~H"""
    <div class="yc-person">
      <.avatar person={@person} />
      <div class="yc-person-body">
        <.link navigate={~p"/a/#{@person.id}"} class="yc-name">{@person.name || "Participant"}</.link>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
    </div>
    """
  end

  attr :step, :string, required: true

  def steps(assigns) do
    assigns =
      assign(assigns, :steps, [
        {"pick", "Pick your Council"},
        {"why", "Say why"},
        {"publish", "Publish"},
        {"invite", "Invite"}
      ])

    assigns =
      assign(assigns, :index, Enum.find_index(assigns.steps, &(elem(&1, 0) == assigns.step)) || 1)

    ~H"""
    <ol class="yc-steps" aria-label="Council setup progress">
      <li
        :for={{{key, label}, i} <- Enum.with_index(@steps)}
        class={["yc-step", i == @index && "current", i < @index && "done"]}
        aria-current={key == @step && "step"}
      >
        <b>{if i < @index, do: "✓", else: i + 1}</b><span>{label}</span>
      </li>
    </ol>
    """
  end

  attr :summary, :map, required: true

  def position_bar(assigns) do
    ~H"""
    <div
      class="yc-vote-bar"
      role="img"
      aria-label={"#{@summary.for} For, #{@summary.against} Against, #{@summary.abstain} Abstain, #{@summary.missing} with no eligible position"}
    >
      <span class={["yes", width_class(@summary.for, @summary.total)]}></span>
      <span class={["no", width_class(@summary.against, @summary.total)]}></span>
      <span class={["other", width_class(@summary.abstain + @summary.missing, @summary.total)]}>
      </span>
    </div>
    <p class="yc-help">
      <strong class="yc-for">{@summary.for} For</strong>
      · <strong class="yc-against">{@summary.against} Against</strong>
      · {@summary.abstain} Abstain · {@summary.missing} no eligible position
    </p>
    """
  end

  def people_count(1), do: "1 person"
  def people_count(count), do: "#{count} people"

  def initials(nil), do: "?"

  def initials(name),
    do:
      name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1) |> String.upcase()

  def biography(person), do: YouCongressWeb.SEO.truncate(person.bio || "", 90)
  def answer(nil), do: "No position"
  def answer(value), do: value |> to_string() |> String.capitalize()
  defp width_class(_, 0), do: "w-percent-0"
  defp width_class(n, total), do: "w-percent-#{round(100 * n / total)}"
end
