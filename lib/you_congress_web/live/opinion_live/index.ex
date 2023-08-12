defmodule YouCongressWeb.OpinionLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :opinions, Opinions.list_opinions())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Opinion")
    |> assign(:opinion, Opinions.get_opinion!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Opinion")
    |> assign(:opinion, %Opinion{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Opinions")
    |> assign(:opinion, nil)
  end

  @impl true
  def handle_info({YouCongressWeb.OpinionLive.FormComponent, {:saved, opinion}}, socket) do
    {:noreply, stream_insert(socket, :opinions, opinion)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    opinion = Opinions.get_opinion!(id)
    {:ok, _} = Opinions.delete_opinion(opinion)

    {:noreply, stream_delete(socket, :opinions, opinion)}
  end
end
