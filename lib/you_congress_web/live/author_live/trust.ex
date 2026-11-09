defmodule YouCongressWeb.AuthorLive.Trust do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Authors, Councils}
  alias YouCongress.Councils.Discovery
  alias YouCongressWeb.AuthorPaths

  @impl true
  def mount(_, session, socket) do
    {:ok, socket |> assign_current_user(session["user_token"]) |> assign(:full_width, true)}
  end

  @impl true
  def handle_params(params, _, socket) do
    person =
      case params do
        %{"username" => username} -> Authors.get_author_by!(username: username)
        %{"id" => id} -> Authors.get_author!(id)
      end

    cond do
      params["tab"] == "statements" ->
        {:noreply, push_navigate(socket, to: AuthorPaths.profile(person))}

      params["id"] && person.username not in [nil, ""] ->
        {:noreply, push_navigate(socket, to: AuthorPaths.trust(person))}

      true ->
        selected =
          if socket.assigns.current_user,
            do: Councils.delegate_ids(socket.assigns.current_user.author_id),
            else: []

        {:noreply,
         assign(socket,
           person: person,
           selected: selected,
           reasons: Discovery.public_reasons(person.id),
           page_title: "Why people trust #{person.name}",
           canonical_url: YouCongressWeb.Endpoint.url() <> AuthorPaths.trust(person)
         )}
    end
  end
end
