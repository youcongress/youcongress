defmodule YouCongressWeb.VoteLive.Index do
  use YouCongressWeb, :live_view

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()
      |> stream(:votes, Votes.list_votes())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Vote")
    |> assign(:vote, Votes.get_vote!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Vote")
    |> assign(:vote, %Vote{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Votes")
    |> assign(:vote, nil)
  end

  @impl true
  def handle_info({YouCongressWeb.VoteLive.FormComponent, {:saved, vote}}, socket) do
    {:noreply, stream_insert(socket, :votes, vote)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    vote = Votes.get_vote!(id)
    {:ok, _} = Votes.delete_vote(vote)

    {:noreply, stream_delete(socket, :votes, vote)}
  end
end
