defmodule YouCongressWeb.VotingLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votings
  alias YouCongress.Votings.Voting

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :votings, Votings.list_votings())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Voting")
    |> assign(:voting, Votings.get_voting!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Voting")
    |> assign(:voting, %Voting{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Votings")
    |> assign(:voting, nil)
  end

  @impl true
  def handle_info({YouCongressWeb.VotingLive.FormComponent, {:saved, voting}}, socket) do
    {:noreply, stream_insert(socket, :votings, voting)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    voting = Votings.get_voting!(id)
    {:ok, _} = Votings.delete_voting(voting)

    {:noreply, stream_delete(socket, :votings, voting)}
  end
end
