defmodule YouCongressWeb.TrustLive.PeopleLists do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Repo, PeopleLists, Councils, TrustRankings}
  alias YouCongress.Councils.Discovery

  @impl true
  def mount(_, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     assign(socket,
       full_width: true,
       page_title: "People lists",
       list: nil,
       owner: nil,
       lists: [],
       people: %{},
       matches: [],
       query: "",
       own: false,
       draft: %{name: "", version: 1, members: []}
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    user = socket.assigns.current_user

    case socket.assigns.live_action do
      :index ->
        index(socket, params)

      :new when not is_nil(user) ->
        members = if params["from"] == "council", do: council_members(user), else: []
        draft = %{name: "", version: 1, members: members}

        {:noreply,
         socket
         |> assign(
           draft: draft,
           list: nil,
           owner: user.author,
           own: true,
           page_title: "Create a public list"
         )
         |> load_people()}

      action when action in [:show, :edit] ->
        load_list(socket, params["id"])

      _ ->
        {:noreply,
         push_navigate(socket, to: YouCongressWeb.ReturnTo.log_in_path(nil, ~p"/lists/new"))}
    end
  end

  defp index(socket, params) do
    user = socket.assigns.current_user
    id = TrustRankings.parse_id(params["author_id"]) || (user && user.author_id)
    owner = if id, do: Repo.get(YouCongress.Authors.Author, id)

    {:noreply,
     assign(socket,
       owner: owner,
       own: user && owner && user.author_id == owner.id,
       lists: if(owner, do: PeopleLists.for_author(owner.id), else: []),
       page_title: "People lists"
     )}
  end

  defp load_list(socket, id) do
    list = PeopleLists.get(id)
    user = socket.assigns.current_user
    own = list && user && list.author_id == user.author_id

    cond do
      is_nil(list) ->
        {:noreply,
         socket
         |> put_flash(:error, "This list is not available.")
         |> push_navigate(to: ~p"/lists")}

      socket.assigns.live_action == :edit && !own ->
        {:noreply, push_navigate(socket, to: ~p"/lists/#{list.id}")}

      true ->
        draft = %{
          name: list.name,
          version: list.version,
          members: Enum.map(list.members, &Map.take(&1, [:author_id, :reason]))
        }

        {:noreply,
         socket
         |> assign(
           list: list,
           owner: Repo.get!(YouCongress.Authors.Author, list.author_id),
           own: own,
           draft: draft,
           page_title: list.name
         )
         |> load_people()}
    end
  end

  @impl true
  def handle_event(_, _, %{assigns: %{own: own}} = socket) when own != true,
    do: {:noreply, socket}

  def handle_event("search", %{"q" => q}, socket) do
    q = String.slice(q, 0, 200)

    {:noreply,
     assign(socket,
       query: q,
       matches: if(String.trim(q) == "", do: [], else: Discovery.search(q))
     )}
  end

  def handle_event("add-person", %{"id" => raw}, socket) do
    id = TrustRankings.parse_id(raw)

    if id && Repo.get(YouCongress.Authors.Author, id) &&
         !Enum.any?(socket.assigns.draft.members, &(&1.author_id == id)) do
      {:noreply,
       socket
       |> assign(
         draft: %{
           socket.assigns.draft
           | members: socket.assigns.draft.members ++ [%{author_id: id, reason: nil}]
         }
       )
       |> load_people()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-person", %{"id" => raw}, socket) do
    members =
      Enum.reject(socket.assigns.draft.members, &(&1.author_id == TrustRankings.parse_id(raw)))

    {:noreply,
     socket |> assign(draft: %{socket.assigns.draft | members: members}) |> load_people()}
  end

  def handle_event("change", params, socket), do: {:noreply, update_draft(socket, params)}

  def handle_event("save", params, socket) do
    socket = update_draft(socket, params)

    result =
      if socket.assigns.list,
        do:
          PeopleLists.update(
            socket.assigns.current_user,
            socket.assigns.list.id,
            socket.assigns.draft
          ),
        else: PeopleLists.create(socket.assigns.current_user, socket.assigns.draft)

    case result do
      {:ok, list} ->
        {:noreply,
         socket
         |> put_flash(:info, "Public list saved. Your private Council is unchanged.")
         |> push_navigate(to: ~p"/lists/#{list.id}")}

      {:error, :stale} ->
        {:noreply,
         put_flash(socket, :error, "This list changed in another window. Reload before saving.")}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Give your list a name (up to 120 characters) and keep reasons under 5,000 characters."
         )}
    end
  end

  def handle_event("delete", _, %{assigns: %{list: list}} = socket) when not is_nil(list) do
    case PeopleLists.delete(socket.assigns.current_user, list.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Public list deleted. Your private Council is unchanged.")
         |> push_navigate(to: ~p"/lists")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete this list.")}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp update_draft(socket, params) do
    draft = socket.assigns.draft
    reasons = params["reasons"] || %{}

    members =
      Enum.map(
        draft.members,
        &Map.put(&1, :reason, Map.get(reasons, to_string(&1.author_id), &1[:reason]))
      )

    assign(socket, draft: %{draft | name: params["name"] || draft.name, members: members})
  end

  defp load_people(socket),
    do:
      assign(socket,
        people: Discovery.people(Enum.map(socket.assigns.draft.members, & &1.author_id))
      )

  defp council_members(user) do
    {:ok, council} = Councils.ensure(user.author_id)

    council.lists
    |> hd()
    |> Map.fetch!(:members)
    |> Enum.map(&Map.take(&1, [:author_id, :reason]))
  end

  def public_url(id), do: YouCongressWeb.Endpoint.url() <> "/lists/#{id}"
end
