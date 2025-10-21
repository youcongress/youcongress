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
        "AI Safety & Governance liquid democracy polls with verifiable quotes | YouCongress"
      )
      |> assign(
        :page_description,
        "Platform that informs citizens, finds solutions and shows legislators how people want to solve our most pressing challenges. Uses verifiable quotes and liquid democracy polls. Starting with AI Safety & Governance."
      )
      |> assign(:skip_page_suffix, true)
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
