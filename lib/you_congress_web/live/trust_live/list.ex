defmodule YouCongressWeb.TrustLive.List do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Councils, Repo, TrustRankings}
  alias YouCongress.Councils.Discovery

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     assign(socket,
       full_width: true,
       page_title: "YouCongress Trust 30",
       tab: "people",
       result: Discovery.trust30(),
       selected: [],
       person: nil,
       reasons: [],
       statements: []
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    selected =
      if socket.assigns.current_user,
        do: Councils.delegate_ids(socket.assigns.current_user.author_id),
        else: []

    socket =
      assign(socket,
        selected: selected,
        tab: if(params["tab"] == "statements", do: "statements", else: "people")
      )

    if socket.assigns.live_action == :person do
      case TrustRankings.parse_id(params["id"]) do
        nil ->
          {:noreply, push_navigate(socket, to: ~p"/trust")}

        id ->
          case Repo.get(YouCongress.Authors.Author, id) do
            nil ->
              {:noreply, push_navigate(socket, to: ~p"/trust")}

            person ->
              {:noreply,
               assign(socket,
                 person: person,
                 page_title: "Why people trust #{person.name}",
                 reasons: Discovery.public_reasons(id),
                 statements: Discovery.statements([id])
               )}
          end
      end
    else
      {:noreply,
       assign(socket,
         person: nil,
         statements: if(socket.assigns.tab == "statements", do: Discovery.statements(), else: [])
       )}
    end
  end
end
