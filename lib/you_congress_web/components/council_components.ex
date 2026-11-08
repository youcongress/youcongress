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
        {"publish", "Publish"},
        {"invite", "Invite"}
      ])

    assigns =
      assign(assigns, :index, Enum.find_index(assigns.steps, &(elem(&1, 0) == assigns.step)) || 0)

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

  attr :member, :map, required: true
  attr :person, :map, required: true
  attr :editing_reason, :integer, default: nil
  attr :reason_text, :string, required: true
  attr :reason_error, :string, default: nil

  def reason_editor(assigns) do
    ~H"""
    <div class="yc-gap-sm">
      <blockquote
        :if={@editing_reason != @member.author_id && @member[:reason] not in [nil, ""]}
        class="yc-note"
      >
        <span>{@member[:reason]}</span>
      </blockquote>
      <form
        :if={@editing_reason == @member.author_id}
        id={"council-reason-#{@member.author_id}"}
        phx-change="change-reason"
        phx-submit="save-reason"
        class="yc-gap-sm"
      >
        <label class="yc-label" for={"inline-reason-#{@member.author_id}"}>
          Why I trust {@person.name}
        </label>
        <textarea
          id={"inline-reason-#{@member.author_id}"}
          name="reason"
          class="yc-field"
          rows="3"
          maxlength="5000"
          phx-debounce="300"
          phx-mounted={JS.focus()}
          aria-invalid={to_string(!is_nil(@reason_error))}
          aria-describedby={@reason_error && "reason-error-#{@member.author_id}"}
        >{@reason_text}</textarea>
        <p
          :if={@reason_error}
          id={"reason-error-#{@member.author_id}"}
          class="text-sm text-red-700 mt-2"
          role="alert"
        >
          {@reason_error}
        </p>
        <div class="yc-row yc-gap-sm">
          <button type="submit" class="yc-btn primary" phx-disable-with="Saving…">
            Save reason
          </button>
          <button type="button" class="yc-btn" phx-click="cancel-reason">Cancel</button>
        </div>
      </form>

      <button
        :if={@editing_reason != @member.author_id}
        type="button"
        phx-click="edit-reason"
        phx-value-id={@member.author_id}
        class="yc-link"
      >
        {if @member[:reason] in [nil, ""], do: "+ Add a reason", else: "Edit reason"}
      </button>
    </div>
    """
  end

  attr :editing_reason, :integer, default: nil
  attr :class, :string, default: "yc-btn primary"
  slot :inner_block, required: true

  def continue_button(assigns) do
    ~H"""
    <button
      type={if @editing_reason, do: "submit", else: "button"}
      form={@editing_reason && "council-reason-#{@editing_reason}"}
      name="continue"
      value="true"
      phx-click={if is_nil(@editing_reason), do: "save"}
      phx-disable-with="Saving…"
      class={@class}
    >
      {render_slot(@inner_block)}
    </button>
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
