defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings.Voting
  alias YouCongressWeb.VotingLive.NewFormComponent

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Finding Solutions to Our Most Important Problems")
      |> assign(:live_action, :new)
      |> assign(:current_user, nil)
      |> assign(:page, :home)

    {:ok, socket}
  end

  @impl true
  def handle_info({NewFormComponent, {:put_flash, level, message}}, socket) do
    {:noreply, put_flash(socket, level, message)}
  end
end
