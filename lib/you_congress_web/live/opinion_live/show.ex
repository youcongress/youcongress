defmodule YouCongressWeb.OpinionLive.Show do
  use YouCongressWeb, :live_view

  alias YouCongress.Opinions
  alias YouCongress.Track
  alias YouCongress.Delegations
  alias YouCongressWeb.AuthorLive
  alias YouCongressWeb.VotingLive.VoteComponent.AiQuoteMenu
  alias YouCongressWeb.Tools.Tooltip

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign_current_user(session["user_token"])
      |> assign_counters()

    if connected?(socket) do
      Track.event("View Opinion", socket.assigns.current_user)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _, socket) do
    opinion = get_opinion!(params)
    parent_opinion = Opinions.get_opinion(opinion.parent_id)
    delegating = Delegations.delegating?(socket.assigns.current_user.author_id, opinion.author_id)

    {:noreply,
     socket
     |> assign(
       page_title: "Opinion",
       opinion: opinion,
       new_opinion: %Opinions.Opinion{},
       parent_opinion: parent_opinion,
       delegating?: delegating
     )}
  end

  defp get_opinion!(%{"id" => user_id}) do
    Opinions.get_opinion!(user_id, preload: [:author, :voting])
  end
end
