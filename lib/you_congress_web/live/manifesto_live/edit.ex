defmodule YouCongressWeb.ManifestoLive.Edit do
  use YouCongressWeb, :live_view

  alias YouCongress.Manifestos
  alias YouCongress.Manifestos.ManifestoSection
  alias YouCongress.Votings
  alias YouCongress.Repo

  @impl true
  def mount(%{"slug" => slug}, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    manifesto = Manifestos.get_manifesto_by_slug!(slug)

    # TODO: Add authorization check here

    {:ok,
     socket
     |> assign(:manifesto, manifesto)
     |> assign(:section_form, to_form(ManifestoSection.changeset(%ManifestoSection{}, %{})))
     |> stream(:sections, manifesto.sections)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, _params) do
    socket
    |> assign(:page_title, "Edit Manifesto")
  end

  @impl true
  def handle_event("save_section", %{"manifesto_section" => section_params}, socket) do
    manifesto = socket.assigns.manifesto
    params = Map.put(section_params, "manifesto_id", manifesto.id)

    case Manifestos.create_section(params) do
      {:ok, section} ->
        # Refresh manifesto to get updated sections if needed or just stream insert
        # Need to reload manifesto really for simplicity or just append
        section = Repo.preload(section, :voting)

        {:noreply,
         socket
         |> put_flash(:info, "Section added")
         |> stream_insert(:sections, section)
         |> assign(:section_form, to_form(ManifestoSection.changeset(%ManifestoSection{}, %{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :section_form, to_form(changeset))}
    end
  end

  def handle_event("delete_section", %{"id" => id}, socket) do
    section = Manifestos.get_section!(id)
    {:ok, _} = Manifestos.delete_section(section)

    {:noreply, stream_delete(socket, :sections, section)}
  end

  # TODO: Implement editing main manifesto details via FormComponent if needed,
  # or just focus on sections as requested.

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-8">
        <.link navigate={~p"/manifestos/#{@manifesto.slug}"} class="text-indigo-600 hover:text-indigo-800">
           &larr; Back to Manifesto
        </.link>
      </div>

      <h1 class="text-2xl font-bold mb-6">Manage Manifesto: <%= @manifesto.title %></h1>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Sections List -->
        <div class="lg:col-span-2 space-y-6">
          <h2 class="text-xl font-semibold">Sections</h2>

          <div id="sections" phx-update="stream" class="space-y-4">
            <div :for={{id, section} <- @streams.sections} id={id} class="bg-white p-4 rounded shadow border border-gray-200 relative group">
              <div class="whitespace-pre-wrap"><%= section.body %></div>

              <div :if={section.voting} class="mt-2 text-sm text-indigo-600 font-medium">
                Linked Motion: <%= section.voting.title %>
              </div>

              <button phx-click="delete_section" phx-value-id={section.id} data-confirm="Are you sure?" class="absolute top-2 right-2 text-red-500 hover:text-red-700 opacity-0 group-hover:opacity-100 transition-opacity">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M9 2a1 1 0 00-.894.553L7.382 4H4a1 1 0 000 2v10a2 2 0 002 2h8a2 2 0 002-2V6a1 1 0 100-2h-3.382l-.724-1.447A1 1 0 0011 2H9zM7 8a1 1 0 012 0v6a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v6a1 1 0 102 0V8a1 1 0 00-1-1z" clip-rule="evenodd" />
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Add Section Form -->
        <div class="bg-gray-50 p-6 rounded-lg h-fit">
          <h2 class="text-lg font-semibold mb-4">Add Paragraph</h2>

          <.simple_form
            for={@section_form}
            phx-submit="save_section"
          >
            <.input field={@section_form[:body]} type="textarea" label="Content" rows={5} placeholder="Write your paragraph..." />
            <.input field={@section_form[:voting_id]} type="number" label="Motion ID (Optional)" placeholder="e.g. 123" />

            <:actions>
              <.button>Add Section</.button>
            </:actions>
          </.simple_form>
        </div>
      </div>
    </div>
    """
  end
end
