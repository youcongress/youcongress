defmodule YouCongressWeb.WelcomeLive.Index do
  use YouCongressWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    if connected?(socket) do
      %{assigns: %{current_user: current_user}} = socket
      YouCongress.Track.event("View Welcome", current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Welcome")
    |> assign(:voting, nil)
  end

  @impl true
end
