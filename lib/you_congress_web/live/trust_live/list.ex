defmodule YouCongressWeb.TrustLive.List do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.Councils
  alias YouCongress.Councils.Discovery

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    result = Discovery.trust30()
    ids = Enum.map(result.rows, & &1.author_id)

    {:ok,
     assign(socket,
       full_width: true,
       page_title: "YouCongress Trust 30",
       tab: "people",
       result: result,
       people: Discovery.people(ids),
       reason_author_ids: Discovery.public_reason_author_ids(ids),
       selected: [],
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

    {:noreply,
     assign(socket,
       statements: if(socket.assigns.tab == "statements", do: Discovery.statements(), else: [])
     )}
  end
end
