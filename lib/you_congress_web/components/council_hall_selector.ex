defmodule YouCongressWeb.Components.CouncilHallSelector do
  @moduledoc "Selects one existing hall for a private Council list."
  use YouCongressWeb, :live_component

  @impl true
  def update(assigns, socket) do
    options =
      [%{id: "general", label: "General", description: "All statements"}] ++
        (assigns.halls
         |> Enum.reject(&(&1.name == "general"))
         |> Enum.sort_by(& &1.name)
         |> Enum.map(&%{id: to_string(&1.id), label: &1.name, description: nil}))

    {:ok,
     socket
     |> assign(assigns)
     |> assign(options: options, selected: to_string(assigns.hall_id || "general"))
     |> assign_new(:editing, fn -> false end)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:selected_index, fn -> 0 end)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        matches: matches(assigns),
        selected_option: Enum.find(assigns.options, &(&1.id == assigns.selected))
      )

    ~H"""
    <div id={@id} class="yc-hall-selector">
      <div class="flex flex-wrap items-center gap-2">
        <span class="inline-flex items-center gap-1 rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-gray-300">
          {@selected_option.label}
        </span>
        <span :if={!@selected_option.description} class="text-xs text-gray-500">hall</span>
        <span :if={@selected_option.description} class="text-xs text-gray-500">
          {@selected_option.description}
        </span>
        <button
          :if={!@fixed}
          type="button"
          phx-click="toggle"
          phx-target={@myself}
          aria-expanded={to_string(@editing)}
          aria-controls={"#{@id}-choices"}
          class="yc-link text-xs"
        >
          {if @editing, do: "Cancel", else: "Change hall"}
        </button>
      </div>
      <form
        :if={@editing && !@fixed}
        id={"#{@id}-choices"}
        phx-change="search"
        phx-submit="choose-highlighted"
        phx-target={@myself}
        class="yc-hall-choices"
      >
        <label for={"#{@id}-search"} class="yc-label">Choose an existing hall</label>
        <input
          id={"#{@id}-search"}
          name="query"
          value={@query}
          type="search"
          autocomplete="off"
          placeholder="Type to search halls…"
          class="yc-field"
          phx-keydown="navigate"
          phx-target={@myself}
          role="combobox"
          aria-autocomplete="list"
          aria-expanded="true"
          aria-controls={"#{@id}-options"}
          aria-activedescendant={if @matches != [], do: "#{@id}-option-#{@selected_index}"}
        />
        <ul id={"#{@id}-options"} role="listbox" aria-label="Existing halls" class="yc-hall-options">
          <li :for={{option, index} <- Enum.with_index(@matches)}>
            <button
              id={"#{@id}-option-#{index}"}
              type="button"
              role="option"
              aria-selected={to_string(index == @selected_index)}
              phx-click="choose"
              phx-value-hall={option.id}
              phx-target={@myself}
              class={["yc-hall-option", index == @selected_index && "is-highlighted"]}
            >
              {option.label}<span :if={option.description} class="text-gray-500"> · {option.description}</span>
            </button>
          </li>
        </ul>
        <p :if={@matches == []} class="yc-help">No existing halls match. Try another name.</p>
      </form>
    </div>
    """
  end

  @impl true
  def handle_event("toggle", _, socket),
    do: {:noreply, assign(socket, editing: !socket.assigns.editing, query: "", selected_index: 0)}

  def handle_event("search", %{"query" => query}, socket),
    do: {:noreply, assign(socket, query: String.slice(query, 0, 100), selected_index: 0)}

  def handle_event("navigate", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, editing: false)}

  def handle_event("navigate", %{"key" => key}, socket) when key in ["ArrowDown", "ArrowUp"] do
    direction = if key == "ArrowDown", do: 1, else: -1

    index =
      max(0, min(socket.assigns.selected_index + direction, length(matches(socket.assigns)) - 1))

    {:noreply, assign(socket, selected_index: index)}
  end

  def handle_event("navigate", _, socket), do: {:noreply, socket}

  def handle_event("choose-highlighted", _, socket) do
    case Enum.at(matches(socket.assigns), socket.assigns.selected_index) do
      nil -> {:noreply, socket}
      option -> choose(socket, option.id)
    end
  end

  def handle_event("choose", %{"hall" => hall}, socket), do: choose(socket, hall)

  defp choose(socket, hall) do
    if !socket.assigns.fixed && Enum.any?(socket.assigns.options, &(&1.id == hall)) do
      send(self(), {:council_hall_selected, socket.assigns.list_id, hall})
      {:noreply, assign(socket, editing: false, query: "", selected_index: 0)}
    else
      {:noreply, socket}
    end
  end

  defp matches(assigns) do
    query = assigns.query |> String.downcase() |> String.replace("-", " ") |> String.trim()

    assigns.options
    |> Enum.filter(
      &String.contains?(&1.label |> String.downcase() |> String.replace("-", " "), query)
    )
    |> Enum.take(12)
  end
end
