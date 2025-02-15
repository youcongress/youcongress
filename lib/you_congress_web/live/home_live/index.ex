defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings.Voting
  alias YouCongressWeb.VotingLive.NewFormComponent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Finding Solutions to Our Most Important Problems")
     |> assign(:live_action, :new)
     |> assign(:current_user, nil),
     layout: false}
  end
end
