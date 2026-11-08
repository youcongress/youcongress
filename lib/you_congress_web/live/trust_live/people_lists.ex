defmodule YouCongressWeb.TrustLive.PeopleLists do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Repo, PeopleLists, Councils, TrustRankings}
  alias YouCongress.Councils.Discovery
  alias YouCongressWeb.PeopleListPaths

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
       slug_custom: false,
       slug_error: nil,
       linked: false,
       original_linked: false,
       reviewing_council: false,
       editing_reason: nil,
       reason_text: "",
       last_added_id: nil,
       autosave: false,
       save_error: nil,
       draft: %{name: "", slug: "", version: 1, members: []}
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
        draft = %{name: "", slug: "", version: 1, members: members}

        {:noreply,
         socket
         |> assign(
           draft: draft,
           linked: params["from"] == "council",
           original_linked: false,
           reviewing_council: params["from"] == "council",
           matches: Discovery.search(""),
           slug_custom: false,
           slug_error: nil,
           list: nil,
           autosave: false,
           save_error: nil,
           owner: user.author,
           own: true,
           page_title: "Create a public list"
         )
         |> load_people()}

      :show ->
        show_list(socket, params)

      :edit ->
        load_list(socket, PeopleLists.get(params["id"]), params["from"])

      _ ->
        {:noreply,
         push_navigate(socket, to: YouCongressWeb.ReturnTo.log_in_path(nil, ~p"/lists/new"))}
    end
  end

  defp show_list(socket, params) do
    owner = list_owner(params)
    list = if owner, do: PeopleLists.get_by_slug(owner.id, params["slug"])

    requested =
      if params["username"],
        do: "/@#{params["username"]}/lists/#{params["slug"]}",
        else: "/a/#{params["author_id"]}/lists/#{params["slug"]}"

    if list && requested != PeopleListPaths.public_path(owner, list.slug) do
      {:noreply, push_navigate(socket, to: PeopleListPaths.public_path(owner, list.slug))}
    else
      load_list(socket, list)
    end
  end

  defp list_owner(%{"username" => username}),
    do: YouCongress.Authors.get_author_by(username: username)

  defp list_owner(%{"author_id" => raw}) do
    case TrustRankings.parse_id(raw) do
      nil -> nil
      id -> Repo.get(YouCongress.Authors.Author, id)
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

  defp load_list(socket, list, source \\ nil) do
    user = socket.assigns.current_user
    own = list && user && list.author_id == user.author_id

    cond do
      is_nil(list) ->
        {:noreply,
         socket
         |> put_flash(:error, "This list is not available.")
         |> push_navigate(to: ~p"/lists")}

      socket.assigns.live_action == :edit && !own ->
        {:noreply, push_navigate(socket, to: PeopleListPaths.public_path(list))}

      true ->
        render_list(socket, list, user, own, source)
    end
  end

  defp render_list(socket, list, user, own, source) do
    linked_list = if own, do: PeopleLists.linked_list(user)
    linked = not is_nil(linked_list) && linked_list.id == list.id
    reviewing = own && socket.assigns.live_action == :edit && source == "council" && linked

    draft = %{
      name: list.name,
      slug: list.slug,
      version: list.version,
      members:
        if(reviewing,
          do: council_members(user),
          else: Enum.map(list.members, &Map.take(&1, [:author_id, :reason]))
        )
    }

    {:noreply,
     socket
     |> assign(
       autosave: socket.assigns.live_action == :edit && !reviewing,
       save_error: nil,
       linked: linked,
       original_linked: linked,
       reviewing_council: reviewing,
       editing_reason: nil,
       reason_text: "",
       last_added_id: nil,
       matches: if(socket.assigns.live_action == :edit, do: Discovery.search(""), else: []),
       query: "",
       list: list,
       owner: Repo.get!(YouCongress.Authors.Author, list.author_id),
       own: own,
       draft: draft,
       slug_custom: true,
       slug_error: nil,
       page_title: list.name
     )
     |> load_people()}
  end

  @impl true
  def handle_event(_, _, %{assigns: %{own: own}} = socket) when own != true,
    do: {:noreply, socket}

  def handle_event("search", %{"q" => q}, socket) do
    q = String.slice(q, 0, 200)

    {:noreply,
     assign(socket,
       query: q,
       matches: Discovery.search(q)
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
           | members: [%{author_id: id, reason: nil} | socket.assigns.draft.members]
         }
       )
       |> assign(last_added_id: id)
       |> load_people()
       |> maybe_autosave()
       |> push_event("council-person-added", %{id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-person", %{"id" => raw}, socket) do
    socket =
      if socket.assigns.editing_reason == TrustRankings.parse_id(raw),
        do: assign(socket, editing_reason: nil, reason_text: ""),
        else: socket

    members =
      Enum.reject(socket.assigns.draft.members, &(&1.author_id == TrustRankings.parse_id(raw)))

    {:noreply,
     socket
     |> assign(draft: %{socket.assigns.draft | members: members})
     |> load_people()
     |> maybe_autosave()}
  end

  def handle_event("edit-reason", %{"id" => raw}, socket) do
    case Enum.find(socket.assigns.draft.members, &(&1.author_id == TrustRankings.parse_id(raw))) do
      nil ->
        {:noreply, socket}

      member ->
        {:noreply,
         assign(socket, editing_reason: member.author_id, reason_text: member.reason || "")}
    end
  end

  def handle_event("cancel-reason", _, socket),
    do: {:noreply, assign(socket, editing_reason: nil, reason_text: "")}

  def handle_event("change", params, socket),
    do: {:noreply, socket |> update_draft(params) |> maybe_autosave()}

  def handle_event("flush-autosave", params, socket) do
    socket = socket |> update_draft(params) |> maybe_autosave()
    {:reply, %{saved: is_nil(socket.assigns.save_error)}, socket}
  end

  def handle_event("retry-autosave", _, socket), do: {:noreply, maybe_autosave(socket)}

  def handle_event("save", params, %{assigns: %{autosave: true}} = socket) do
    socket = socket |> update_draft(params) |> maybe_autosave()

    socket =
      if params["action"] == "close-reason" && is_nil(socket.assigns.save_error),
        do: assign(socket, editing_reason: nil, reason_text: ""),
        else: socket

    {:noreply, socket}
  end

  def handle_event("save", %{"action" => "save-reason"} = params, socket) do
    {:noreply, socket |> update_draft(params) |> save_draft_reason()}
  end

  def handle_event("save", params, socket) do
    socket = socket |> update_draft(params) |> save_draft_reason()

    attrs =
      if socket.assigns.linked != socket.assigns.original_linked,
        do: Map.put(socket.assigns.draft, :link_council, socket.assigns.linked),
        else: socket.assigns.draft

    result =
      if socket.assigns.list,
        do:
          PeopleLists.update(
            socket.assigns.current_user,
            socket.assigns.list.id,
            attrs
          ),
        else: PeopleLists.create(socket.assigns.current_user, attrs)

    case result do
      {:ok, list} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           if(socket.assigns.linked,
             do: "Public list saved. Its people are synced with your Council.",
             else: "Public list saved."
           )
         )
         |> push_navigate(to: PeopleListPaths.public_path(list))}

      {:error, :self_in_linked_list} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "A linked list cannot include yourself. Remove yourself or unlink it from your Council."
         )}

      {:error, :stale} ->
        {:noreply,
         put_flash(socket, :error, "This list changed in another window. Reload before saving.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(slug_error: PeopleListPaths.slug_error(changeset))
         |> put_flash(:error, "Check your list name, URL, and reasons before saving.")}

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

    reason_text =
      Map.get(reasons, to_string(socket.assigns.editing_reason), socket.assigns.reason_text)

    linked =
      if Map.has_key?(params, "link_council"),
        do: params["link_council"] == "true",
        else: socket.assigns.linked

    {draft, custom?} =
      PeopleListPaths.edit_fields(
        draft,
        params,
        socket.assigns.slug_custom,
        socket.assigns.owner.id
      )

    draft =
      if socket.assigns.autosave do
        %{
          draft
          | members:
              Enum.map(draft.members, fn member ->
                Map.put(
                  member,
                  :reason,
                  Map.get(reasons, to_string(member.author_id), member[:reason])
                )
              end)
        }
      else
        draft
      end

    assign(socket,
      draft: draft,
      slug_custom: custom?,
      slug_error: nil,
      linked: linked,
      reason_text: reason_text
    )
  end

  defp maybe_autosave(%{assigns: %{autosave: false}} = socket), do: socket

  defp maybe_autosave(socket) do
    if socket.assigns.draft == saved_draft(socket.assigns.list) &&
         socket.assigns.linked == socket.assigns.original_linked do
      assign(socket, save_error: nil, slug_error: nil)
    else
      persist_autosave(socket)
    end
  end

  defp saved_draft(list) do
    %{
      name: list.name,
      slug: list.slug,
      version: list.version,
      members: Enum.map(list.members, &Map.take(&1, [:author_id, :reason]))
    }
  end

  defp persist_autosave(socket) do
    attrs =
      if socket.assigns.linked != socket.assigns.original_linked,
        do: Map.put(socket.assigns.draft, :link_council, socket.assigns.linked),
        else: socket.assigns.draft

    case PeopleLists.update(socket.assigns.current_user, socket.assigns.list.id, attrs) do
      {:ok, list} ->
        linked = PeopleLists.linked_list(socket.assigns.current_user)
        linked? = not is_nil(linked) && linked.id == list.id

        draft = saved_draft(list)

        assign(socket,
          list: list,
          draft: draft,
          linked: linked?,
          original_linked: linked?,
          save_error: nil,
          slug_error: nil
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        assign(socket,
          slug_error: PeopleListPaths.slug_error(changeset),
          save_error: "Not saved. Check the list name, URL, and reason length."
        )

      {:error, :stale} ->
        assign(socket,
          save_error:
            "Not saved: this list changed in another window or through your Council. Reload to get the latest version; your edits are still shown here."
        )

      {:error, :self_in_linked_list} ->
        assign(socket,
          save_error:
            "Not saved: a linked list cannot include yourself. Remove yourself or unlink the list."
        )

      _ ->
        assign(socket, save_error: "Your changes could not be saved. Please try again.")
    end
  end

  defp save_draft_reason(socket) do
    members =
      Enum.map(socket.assigns.draft.members, fn member ->
        if member.author_id == socket.assigns.editing_reason,
          do: Map.put(member, :reason, socket.assigns.reason_text),
          else: member
      end)

    assign(socket,
      draft: %{socket.assigns.draft | members: members},
      editing_reason: nil,
      reason_text: ""
    )
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
end
