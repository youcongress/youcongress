defmodule YouCongressWeb.ManifestoLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Manifestos

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok, stream(socket, :manifestos, Manifestos.list_active_manifestos())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Manifestos")
    |> assign(:manifesto, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Manifesto")
    |> assign(:manifesto, %YouCongress.Manifestos.Manifesto{})
  end

  @impl true
  def handle_info({YouCongressWeb.ManifestoLive.FormComponent, {:saved, manifesto}}, socket) do
    # Only stream if active, but let's just stream/insert it for now if we want to see it
    # If active logic filters it out, user might be confused. But list_active_manifestos filters.
    # If creators make it active by default, it appears.
    {:noreply, stream_insert(socket, :manifestos, manifesto)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="flex justify-between items-center mb-8">
        <h1 class="text-3xl font-serif font-bold text-gray-900 text-center">Manifestos</h1>
        <.link patch={~p"/manifestos/new"} class="bg-indigo-600 hover:bg-indigo-700 text-white font-bold py-2 px-4 rounded shadow">
          New Manifesto
        </.link>
      </div>

      <div class="grid gap-6 md:grid-cols-2" id="manifestos" phx-update="stream">
        <div :for={{id, manifesto} <- @streams.manifestos} id={id} class="bg-white rounded-lg shadow-sm border border-gray-200 p-6 hover:shadow-md transition-shadow">
          <h2 class="text-xl font-bold mb-2">
            <.link navigate={~p"/manifestos/#{manifesto.slug}"} class="hover:underline">
              <%= manifesto.title %>
            </.link>
          </h2>
          <div class="mt-4 flex justify-end">
             <.link navigate={~p"/manifestos/#{manifesto.slug}"} class="text-sm font-semibold text-indigo-600 hover:text-indigo-500">
              Read & Sign <span aria-hidden="true">&rarr;</span>
            </.link>
          </div>
        </div>
      </div>
    </div>

    <.modal :if={@live_action == :new} id="manifesto-modal" show on_cancel={JS.patch(~p"/manifestos")}>
      <.live_component
        module={YouCongressWeb.ManifestoLive.FormComponent}
        id={@manifesto.id || :new}
        title={@page_title}
        action={@live_action}
        manifesto={@manifesto}
        current_user={@current_user}
        patch={~p"/manifestos"}
      />
    </.modal>
    """
  end
end
