defmodule YouCongressWeb.Components.CouncilBookmark do
  @moduledoc "Add or remove one person from the current user's Council."
  use YouCongressWeb, :live_component
  alias YouCongress.Councils

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
  def handle_event("bookmark", _, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, assign(socket, open: true)}

  def handle_event("bookmark", _, socket) do
    %{current_user: user, author_id: id} = socket.assigns
    {:ok, council} = Councils.ensure(user.author_id)

    if id in Councils.delegate_ids(user.author_id) do
      {:noreply,
       assign(socket, council: council, saved: true, open: true, expanded: true, error: nil)}
    else
      case Councils.add_member(user, id) do
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

        _ ->
          {:noreply,
           assign(socket, open: true, error: "Could not add this person to your Council.")}
      end
    end
  end

  def handle_event("remove", _, %{assigns: %{current_user: user, council: council}} = socket)
      when not is_nil(user) and not is_nil(council) do
    case Councils.set_member_lists(user, socket.assigns.author_id, [], council.version) do
      {:ok, council} ->
        {:noreply, assign(socket, council: council, saved: false, open: false, expanded: false)}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           council: Councils.get(user.author_id),
           error: "Your Council changed elsewhere. Review it and try again."
         )}

      _ ->
        {:noreply, assign(socket, error: "Could not update your Council.")}
    end
  end

  def handle_event("dismiss", %{"notice" => notice}, socket) do
    if to_string(socket.assigns.notice) == to_string(notice) and not socket.assigns.expanded,
      do: {:noreply, assign(socket, open: false)},
      else: {:noreply, socket}
  end

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, open: false, expanded: false)}

  def handle_event(_, _, socket), do: {:noreply, socket}

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
        class="fixed bottom-5 right-4 z-[60] w-80 max-w-[calc(100vw-2rem)] rounded-xl border border-gray-200 bg-white p-4 text-sm text-gray-900 shadow-xl"
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
        <p :if={@error} role="alert" class="pr-6 text-red-700">{@error}</p>
        <%= cond do %>
          <% is_nil(@current_user) -> %>
            <p class="pr-6 font-medium">Sign in to add {@name} to your Council.</p>
            <YouCongressWeb.Components.LoginButtons.render
              class="mt-3"
              return_to={~p"/council"}
              pending_actions={Jason.encode!(%{delegate_ids: [@author_id], votes: %{}})}
            />
          <% @expanded -> %>
            <h2 tabindex="-1" data-council-heading class="pr-6 font-semibold">
              {@name} is in your Council
            </h2>
            <p class="mt-2 text-gray-600">Their position counts when you haven’t voted directly.</p>
            <.link navigate={~p"/council?#{%{step: "why"}}"} class="mt-3 block text-indigo-700">
              Add or edit your reason →
            </.link>
            <button class="mt-3 text-red-700" phx-click="remove" phx-target={@myself}>
              Remove from my Council
            </button>
          <% !@error -> %>
            <p role="status" class="pr-6 font-medium">Added to your Council.</p>
            <.link navigate={~p"/council?#{%{step: "why"}}"} class="mt-2 block text-indigo-700">
              Say why you chose them →
            </.link>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end
end
