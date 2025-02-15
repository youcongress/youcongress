defmodule YouCongressWeb.HomeLive.Index do
  use YouCongressWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: false}
  end
end
