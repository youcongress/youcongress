defmodule YouCongressWeb.CouncilComponents do
  @moduledoc "Shared Council, Trust 30, and vote explanation presentation."
  use YouCongressWeb, :html

  attr :current_user, :any, required: true
  attr :active, :atom, required: true

  def council_tabs(assigns) do
    ~H"""
    <nav class="yc-tabs yc-council-tabs" aria-label="My Council">
      <.link
        navigate={~p"/council"}
        class={@active == :order && "active"}
        aria-current={@active == :order && "page"}
      >
        My Council
      </.link>
      <.link
        navigate={~p"/council?#{%{step: "votes"}}"}
        class={@active == :votes && "active"}
        aria-current={@active == :votes && "page"}
      >
        My votes
      </.link>
      <.link
        navigate={~p"/council?#{%{step: "invite"}}"}
        class={@active == :invite && "active"}
        aria-current={@active == :invite && "page"}
      >
        Invites
      </.link>
      <.link
        navigate={~p"/lists"}
        class={@active == :lists && "active"}
        aria-current={@active == :lists && "page"}
      >
        My lists
      </.link>
      <.link
        :if={YouCongress.Accounts.admin?(@current_user)}
        navigate={~p"/trust"}
        class={@active == :trust && "active"}
        aria-current={@active == :trust && "page"}
      >
        Trust 30
      </.link>
    </nav>
    """
  end

  attr :person, :map, required: true
  attr :large, :boolean, default: false

  def avatar(assigns) do
    ~H"""
    <.profile_avatar
      name={@person.name}
      image_url={Map.get(@person, :profile_image_url) || Map.get(@person, :image)}
      class={["yc-avatar", @large && "big"]}
    />
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

  attr :owner, :map, required: true
  attr :slug, :string, required: true
  attr :error, :string, default: nil

  attr :debounce, :string, default: "300"

  def list_slug_field(assigns) do
    ~H"""
    <label class="yc-label yc-gap" for="public-list-slug">List URL</label>
    <input
      id="public-list-slug"
      class="yc-field"
      name="slug"
      value={@slug}
      placeholder="e.g. people-i-trust"
      required
      maxlength="80"
      phx-debounce={@debounce}
      aria-invalid={to_string(!is_nil(@error))}
      aria-describedby="public-list-slug-help"
    />
    <p id="public-list-slug-help" class="yc-help">
      Use lowercase letters, numbers, and hyphens. Old links keep working if you change this.
    </p>
    <p :if={@error} class="text-sm text-red-700 mt-2" role="alert">List URL: {@error}</p>
    <p id="public-list-url-preview" class="yc-help yc-break">
      {YouCongressWeb.PeopleListPaths.public_url(
        @owner,
        if(@slug == "", do: "your-list", else: @slug)
      )}
    </p>
    <p :if={@owner.username in [nil, ""]} class="yc-help">
      <.link navigate={~p"/settings"} class="yc-link">Choose a username</.link>
      to use /@username/lists/{if @slug == "", do: "your-list", else: @slug}.
    </p>
    """
  end

  def people_count(1), do: "1 person"
  def people_count(count), do: "#{count} people"

  def initials(name), do: avatar_initials(name)

  def biography(person), do: YouCongressWeb.SEO.truncate(person.bio || "", 90)
  def answer(nil), do: "No position"
  def answer(value), do: value |> to_string() |> String.capitalize()
  defp width_class(_, 0), do: "w-percent-0"
  defp width_class(n, total), do: "w-percent-#{round(100 * n / total)}"
end
