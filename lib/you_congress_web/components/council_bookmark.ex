defmodule YouCongressWeb.Components.CouncilBookmark do
  @moduledoc "Quick council saving and inline list selection, shared by person actions."
  use YouCongressWeb, :live_component
  alias YouCongress.{Councils, TrustRankings}

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
      |> assign_new(:open, fn -> false end)
      |> assign_new(:expanded, fn -> false end)
      |> assign_new(:council, fn -> nil end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:notice, fn -> 0 end)
    end)
  end

  @impl true
  def handle_event("bookmark", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, assign(socket, open: true, expanded: false)}
  end

  def handle_event("bookmark", _, socket) do
    %{current_user: user, author_id: author_id} = socket.assigns
    {:ok, council} = Councils.ensure(user.author_id)

    if selected?(council, author_id) do
      {:noreply,
       assign(socket, council: council, saved: true, open: true, expanded: true, error: nil)}
    else
      case Councils.add_member(user, author_id) do
        {:ok, council} ->
          {:noreply,
           assign(socket,
             council: council,
             saved: true,
             open: true,
             expanded: false,
             error: nil,
             notice: socket.assigns.notice + 1
           )}

        {:error, _} ->
          {:noreply,
           assign(socket, open: true, error: "Could not add this person. Please try again.")}
      end
    end
  end

  def handle_event("choose-lists", _, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    {:ok, council} = Councils.ensure(user.author_id)
    {:noreply, assign(socket, council: council, expanded: true, error: nil)}
  end

  def handle_event("choose-lists", _, socket), do: {:noreply, socket}

  def handle_event("select-lists", %{"lists" => ids}, socket)
      when is_list(ids) and not is_nil(socket.assigns.current_user) and
             not is_nil(socket.assigns.council) do
    %{current_user: user, author_id: author_id, council: council} = socket.assigns
    ids = ids |> Enum.map(&TrustRankings.parse_id/1) |> Enum.reject(&is_nil/1)

    case Councils.set_member_lists(user, author_id, ids, council.version) do
      {:ok, saved} ->
        {:noreply, assign(socket, council: saved, saved: selected?(saved, author_id), error: nil)}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           council: Councils.get(user.author_id),
           error: "Your council changed elsewhere. Review these lists and try again."
         )}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not save these lists. Please try again.")}
    end
  end

  def handle_event("select-lists", _, socket), do: {:noreply, socket}

  def handle_event("dismiss", %{"notice" => notice}, socket) do
    if to_string(socket.assigns.notice) == to_string(notice) and not socket.assigns.expanded,
      do: {:noreply, assign(socket, open: false)},
      else: {:noreply, socket}
  end

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, open: false, expanded: false)}

  defp selected?(council, author_id), do: Enum.any?(council.lists, &member?(&1, author_id))
  defp member?(list, author_id), do: Enum.any?(list.members, &(&1.author_id == author_id))

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="inline-block text-left"
      phx-hook="CouncilBookmark"
      phx-target={@myself}
      data-open={to_string(@open)}
      data-expanded={to_string(@expanded)}
      data-notice={@notice}
    >
      <button
        type="button"
        phx-click="bookmark"
        phx-target={@myself}
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        aria-controls={@id <> "-popup"}
        class="inline-flex items-center gap-1 rounded bg-indigo-50 px-2 py-1 text-xs font-semibold text-indigo-700 hover:bg-indigo-100 focus-visible:outline focus-visible:outline-2 focus-visible:outline-indigo-600"
      >
        <.icon name={if @saved, do: "hero-bookmark-solid", else: "hero-bookmark"} class="h-4 w-4" />
        {if @saved, do: "In my council", else: "Add to council"}
      </button>
      <div
        :if={@open}
        id={@id <> "-popup"}
        role="dialog"
        aria-label={"Council lists for #{@name}"}
        phx-click-away="close"
        phx-target={@myself}
        phx-window-keydown="close"
        phx-key="Escape"
        class={[
          "fixed bottom-5 right-4 z-[60] max-w-[calc(100vw-2rem)] rounded-xl border border-gray-200 bg-white p-4 text-sm text-gray-900 shadow-xl",
          if(@expanded, do: "w-96", else: "w-80")
        ]}
      >
        <button
          type="button"
          phx-click="close"
          phx-target={@myself}
          aria-label="Close council popup"
          class="absolute right-2 top-2 rounded p-1 text-gray-500 hover:bg-gray-100"
        >
          <.icon name="hero-x-mark" class="h-4 w-4" />
        </button>
        <p :if={@error} role="alert" class="pr-6 text-red-700">{@error}</p>
        <%= cond do %>
          <% is_nil(@current_user) -> %>
            <p class="pr-6 font-medium">Sign in to add {@name} to your council.</p>
            <YouCongressWeb.Components.LoginButtons.render
              class="mt-3"
              return_to={~p"/council"}
              pending_actions={Jason.encode!(%{delegate_ids: [@author_id], votes: %{}})}
            />
          <% @expanded && @council -> %>
            <h2 tabindex="-1" data-council-heading class="pr-6 font-semibold">
              Choose lists for {@name}
            </h2>
            <p class="mt-1 text-xs text-gray-500">
              Changes save automatically. Choose as many lists as you like.
            </p>
            <form
              phx-change="select-lists"
              phx-target={@myself}
              class="mt-3 space-y-1 max-h-72 overflow-y-auto"
            >
              <input type="hidden" name="lists[]" value="" />
              <label
                :for={list <- @council.lists}
                class="flex cursor-pointer items-center gap-3 rounded-lg p-2 hover:bg-gray-50"
              >
                <input
                  type="checkbox"
                  name="lists[]"
                  value={list.id}
                  checked={member?(list, @author_id)}
                  class="rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                />
                <span>
                  <span class="block font-medium">{list.name}</span>
                  <span class="text-xs text-gray-500">
                    List {list.position + 1}{if list.fallback, do: " · Final General fallback"}
                  </span>
                </span>
              </label>
            </form>
            <button
              type="button"
              phx-click="close"
              phx-target={@myself}
              class="mt-3 w-full rounded-lg bg-indigo-600 px-3 py-2 font-semibold text-white hover:bg-indigo-700"
            >
              Done
            </button>
          <% !@error -> %>
            <p role="status" class="pr-6 font-medium">Added to the General council.</p>
            <button
              type="button"
              phx-click="choose-lists"
              phx-target={@myself}
              class="mt-2 font-semibold text-indigo-700 hover:underline"
            >
              Choose lists
            </button>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end
end
