defmodule YouCongressWeb.VotingLive.HallsInputComponent do
  use YouCongressWeb, :live_component

  alias YouCongress.Halls

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <label class="block text-sm font-medium text-gray-700">
        Halls
      </label>
      <div class="flex flex-wrap gap-2 mb-2">
        <%= for hall_name <- @selected_halls do %>
          <span class="inline-flex items-center gap-1 rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10">
            <%= String.replace(hall_name, "-", " ") %>
            <button
              type="button"
              phx-click="remove_hall"
              phx-value-hall={hall_name}
              phx-target={@myself}
              class="text-gray-400 hover:text-gray-600"
            >
              <.icon name="hero-x-mark" class="h-3 w-3" />
            </button>
          </span>
        <% end %>
      </div>

      <div class="flex gap-2">
        <div class="relative flex-grow">
          <div class="flex gap-2">
            <div class="relative flex-grow">
              <input
                type="text"
                value={@typed_value}
                name="value"
                placeholder="Type to search halls..."
                autocomplete="off"
                phx-change="suggest"
                phx-target={@myself}
                phx-debounce="200"
                class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-indigo-600 sm:text-sm sm:leading-6"
              />

              <%= if @matches != [] do %>
                <div class="absolute z-50 w-full mt-1 bg-white rounded-md shadow-lg border border-gray-200">
                  <ul class="py-1">
                    <%= for {name, display_name} <- @matches do %>
                      <li>
                        <button
                          type="button"
                          phx-click="select_match"
                          phx-value-match={name}
                          phx-target={@myself}
                          class="w-full px-4 py-2 text-sm text-left text-gray-700 hover:bg-gray-100"
                        >
                          <%= display_name %>
                        </button>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>

            <button
              type="button"
              phx-click="add_typed_hall"
              phx-target={@myself}
              class="rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
            >
              Add
            </button>
          </div>
        </div>
      </div>

      <%= for {field, _} <- @form.errors do %>
        <div class="text-sm text-red-600">
          <%= Phoenix.HTML.Form.error_tag(@form, field) %>
        </div>
      <% end %>

      <%= for hall_name <- @selected_halls do %>
        <input type="hidden" name={@form[:halls].name <> "[]"} value={hall_name} />
      <% end %>
    </div>
    """
  end

  @impl true
  def update(%{form: form} = assigns, socket) do
    selected_halls = get_selected_halls(form)

    socket =
      socket
      |> assign(assigns)
      |> assign(
        selected_halls: selected_halls,
        typed_value: "",
        matches: []
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("suggest", %{"value" => prefix}, socket) do
    matches =
      if prefix != "" do
        Halls.list_halls(name_contains: prefix)
        |> Enum.map(fn hall -> {hall.name, String.replace(hall.name, "-", " ")} end)
      else
        []
      end

    {:noreply, assign(socket, matches: matches, typed_value: prefix)}
  end

  def handle_event("select_match", %{"match" => match}, socket) do
    {:noreply, add_hall(socket, match)}
  end

  def handle_event("add_typed_hall", _params, %{assigns: %{typed_value: ""}} = socket) do
    {:noreply, socket}
  end

  def handle_event("add_typed_hall", _params, %{assigns: %{typed_value: hall}} = socket) do
    # Convert the input to kebab-case format
    hall = String.downcase(hall) |> String.replace(~r/[^a-z0-9]+/, "-")
    {:noreply, add_hall(socket, hall)}
  end

  def handle_event("remove_hall", %{"hall" => hall}, socket) do
    selected_halls = List.delete(socket.assigns.selected_halls, hall)
    {:noreply, assign(socket, selected_halls: selected_halls, matches: [])}
  end

  defp get_selected_halls(form) do
    values = Phoenix.HTML.Form.input_value(form, :halls)
    case values do
      halls when is_list(halls) ->
        Enum.map(halls, fn
          %{name: name} -> name
          name when is_binary(name) -> name
        end)
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
    end
  end

  defp add_hall(socket, hall) do
    if hall in socket.assigns.selected_halls do
      assign(socket, typed_value: "", matches: [])
    else
      assign(socket,
        selected_halls: [hall | socket.assigns.selected_halls],
        typed_value: "",
        matches: []
      )
    end
  end
end
