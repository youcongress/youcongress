defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongressWeb.VotingLive.NewFormComponent

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    current_user = socket.assigns.current_user

    socket =
      socket
      |> assign(
        :page_title,
        "Liquid Democracy on AI Policy"
      )
      |> assign(:live_action, :new)
      |> assign(:current_user, current_user)
      |> assign(:page, :home)

    {:ok, socket}
  end

  @impl true
  def handle_info({NewFormComponent, {:put_flash, level, message}}, socket) do
    {:noreply, put_flash(socket, level, message)}
  end
end
