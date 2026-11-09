defmodule YouCongressWeb.Components.CouncilBookmark do
  @moduledoc "Choose which owned Council lists include a person."
  use YouCongressWeb, :live_component
  import Ecto.Query
  alias YouCongress.{Councils, Halls, Repo, TrustRankings}

  @impl true
  def update_many(assigns_sockets) do
    memberships =
      assigns_sockets
      |> Enum.map(fn {assigns, _} -> assigns.current_user end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.author_id)
      |> Map.new(fn user -> {user.author_id, Councils.delegate_ids(user.author_id)} end)

    Enum.map(assigns_sockets, fn {assigns, socket} ->
      ids = if assigns.current_user, do: memberships[assigns.current_user.author_id], else: []

      socket
      |> assign(assigns)
      |> assign(:saved, assigns.author_id in ids)
      |> assign_new(:refresh_statement, fn -> false end)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:opening, fn -> 0 end)
      |> assign_new(:council, fn -> nil end)
      |> assign_new(:hall_names, fn -> %{} end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:status, fn -> nil end)
    end)
  end

  @impl true
  def handle_event("bookmark", _, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, open_picker(socket)}

  def handle_event("bookmark", _, socket) do
    author_id = socket.assigns.current_user.author_id
    council = Councils.get(author_id) || elem(Councils.ensure(author_id), 1)
    socket = socket |> load_council(council) |> open_picker()
    last_all = council.lists |> Enum.reverse() |> Enum.find(&is_nil(&1.hall_id))

    cond do
      socket.assigns.saved ->
        {:noreply, socket}

      editable?(last_all, socket.assigns.current_user) ->
        update_selection(socket, last_all.id, true)

      true ->
        {:noreply,
         assign(socket,
           error:
             "The last All statements list is read-only or unavailable. Choose another list below."
         )}
    end
  end

  def handle_event(
        "toggle-list",
        params,
        %{assigns: %{current_user: user, council: council}} = socket
      )
      when not is_nil(user) and not is_nil(council) do
    list_id = TrustRankings.parse_id(params["list_id"])
    list = Enum.find(council.lists, &(&1.id == list_id))

    if editable?(list, user) do
      update_selection(socket, list_id, params["selected"] == "true")
    else
      {:noreply, assign(socket, error: "You can only change lists you own.", status: nil)}
    end
  end

  def handle_event("dismiss", %{"opening" => opening}, socket) do
    if opening == socket.assigns.opening && is_nil(socket.assigns.error),
      do: {:noreply, assign(socket, open: false)},
      else: {:noreply, socket}
  end

  def handle_event("close", _, socket), do: {:noreply, assign(socket, open: false)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  defp open_picker(socket),
    do: assign(socket, open: true, opening: socket.assigns.opening + 1, error: nil, status: nil)

  defp update_selection(socket, list_id, selected) do
    attrs = Councils.editable(socket.assigns.council)

    lists =
      Enum.map(attrs.lists, fn item ->
        if item.id == list_id,
          do: %{item | members: select_member(item.members, socket.assigns.author_id, selected)},
          else: item
      end)

    save_selection(
      socket,
      Councils.save(socket.assigns.current_user, %{attrs | lists: lists}, refresh: :async)
    )
  end

  defp select_member(members, author_id, false),
    do: Enum.reject(members, &(&1.author_id == author_id))

  defp select_member(members, author_id, true) do
    if Enum.any?(members, &(&1.author_id == author_id)),
      do: members,
      else: members ++ [%{author_id: author_id}]
  end

  defp save_selection(socket, {:ok, council}) do
    if socket.assigns.refresh_statement, do: send(self(), :reload)
    {:noreply, socket |> load_council(council) |> assign(error: nil, status: "Changes saved")}
  end

  defp save_selection(socket, {:error, :stale}) do
    {:noreply,
     socket
     |> load_council(Councils.get(socket.assigns.current_user.author_id))
     |> assign(
       error: "Your Council changed elsewhere. Choices have been refreshed. Please try again.",
       status: nil
     )}
  end

  defp save_selection(socket, _),
    do:
      {:noreply,
       assign(socket, error: "Could not update your Council. Please try again.", status: nil)}

  defp load_council(socket, council) do
    hall_ids = council.lists |> Enum.map(& &1.hall_id) |> Enum.reject(&is_nil/1)

    names =
      Repo.all(from h in Halls.Hall, where: h.id in ^hall_ids, select: {h.id, h.name})
      |> Map.new()

    assign(socket,
      council: council,
      hall_names: names,
      saved: Enum.any?(council.lists, &includes?(&1, socket.assigns.author_id))
    )
  end

  defp includes?(list, author_id), do: Enum.any?(list.members, &(&1.author_id == author_id))
  defp editable?(nil, _), do: false
  defp editable?(list, user), do: list.available && list.list_owner_id == user.author_id
  defp hall_name(%{hall_id: nil}, _names), do: "All statements"

  defp hall_name(list, names) do
    case names[list.hall_id] do
      "ai-governance" -> "AI governance"
      "impact-on-labor" -> "Impact on labor"
      name -> YouCongress.Tools.StringUtils.titleize_hall(name || "Hall")
    end
  end

  defp shared_count(council, list),
    do: Enum.count(council.lists, &(&1.people_list_id == list.people_list_id))

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="inline-block text-left"
      phx-hook="CouncilBookmark"
      phx-target={@myself}
      data-open={to_string(@open)}
      data-opening={@opening}
      data-error={to_string(!is_nil(@error))}
    >
      <button
        type="button"
        phx-click="bookmark"
        phx-target={@myself}
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        aria-controls={@id <> "-popup"}
        class="inline-flex items-center gap-1 rounded bg-indigo-50 px-2 py-1 text-xs font-semibold text-indigo-700 hover:bg-indigo-100"
      >
        <.icon name={if @saved, do: "hero-bookmark-solid", else: "hero-bookmark"} class="h-4 w-4" />{if @saved,
          do: "In my Council",
          else: "Add to Council"}
      </button>
      <div
        :if={@open}
        id={@id <> "-popup"}
        role="dialog"
        aria-label={"Council selection for #{@name}"}
        phx-click-away="close"
        phx-target={@myself}
        phx-window-keydown="close"
        phx-key="Escape"
        class="fixed bottom-5 right-4 z-[60] flex max-h-[calc(100dvh-2.5rem)] w-96 max-w-[calc(100vw-2rem)] flex-col overflow-y-auto rounded-xl border border-gray-200 bg-white p-4 text-sm text-gray-900 shadow-xl"
      >
        <button
          type="button"
          phx-click="close"
          phx-target={@myself}
          aria-label="Close Council popup"
          class="absolute right-2 top-2 rounded p-1 text-gray-500"
        >
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
        <%= if is_nil(@current_user) do %>
          <p tabindex="-1" data-council-heading class="pr-6 font-medium">
            Sign in to add {@name} to your Council.
          </p>
          <YouCongressWeb.Components.LoginButtons.render
            class="mt-3"
            return_to={~p"/council"}
            pending_actions={Jason.encode!(%{delegate_ids: [@author_id], votes: %{}})}
          />
        <% else %>
          <h2 tabindex="-1" data-council-heading class="pr-6 text-base font-semibold">
            Choose Council lists
          </h2>
          <p class="mt-1 font-medium">{@name}</p>
          <p class="mt-1 text-gray-600">Choose one or more. Changes save automatically.</p>
          <div class="mt-3 space-y-2">
            <form
              :for={{list, index} <- Enum.with_index(@council.lists)}
              id={"#{@id}-list-#{list.id}"}
              phx-change="toggle-list"
              phx-submit="toggle-list"
              phx-target={@myself}
              class="rounded-lg border border-gray-200 p-3"
            >
              <input type="hidden" name="list_id" value={list.id} />
              <input type="hidden" name="selected" value="false" />
              <label class={[
                "flex items-start gap-3",
                !editable?(list, @current_user) && "text-gray-500"
              ]}>
                <input
                  type="checkbox"
                  name="selected"
                  value="true"
                  checked={includes?(list, @author_id)}
                  disabled={!editable?(list, @current_user)}
                  class="mt-1 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                <span class="min-w-0 break-words">
                  <span class="block font-semibold">{index + 1}. {hall_name(list, @hall_names)}</span>
                  <span class="block text-xs text-gray-600">
                    {list.name} · {if list.public, do: "Public", else: "Private"}
                  </span>
                  <span :if={!list.available} class="mt-1 block text-xs">
                    List unavailable. Choose another list in My Council.
                  </span>
                  <span
                    :if={list.available && !editable?(list, @current_user)}
                    class="mt-1 block text-xs"
                  >
                    Someone else’s list · Read-only. Make a private copy in My Council to edit it.
                  </span>
                  <span
                    :if={list.available && shared_count(@council, list) > 1}
                    class="mt-1 block text-xs"
                  >
                    Same list used in {shared_count(@council, list)} entries. These choices stay in sync.
                  </span>
                </span>
              </label>
            </form>
          </div>
          <p class="mt-3 text-xs text-gray-500">
            Editing a public list changes it for everyone who uses it. Your Council choices stay private.
          </p>
          <p :if={@error} role="alert" class="mt-3 text-red-700">{@error}</p>
          <p :if={@status} role="status" class="mt-3 text-green-700">{@status}</p>
          <div class="mt-3 flex items-center justify-between gap-3">
            <.link navigate={~p"/council"} class="text-indigo-700">My Council →</.link>
            <button
              type="button"
              class="rounded bg-indigo-600 px-4 py-2 font-semibold text-white"
              phx-click="close"
              phx-target={@myself}
            >
              Done
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
