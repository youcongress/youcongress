defmodule YouCongressWeb.WelcomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings.Voting

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])

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
  def handle_info({YouCongressWeb.VotingLive.NewFormComponent, {:put_flash, type, msg}}, socket) do
    {:noreply, put_flash(socket, type, msg)}
  end

  @impl true
end
