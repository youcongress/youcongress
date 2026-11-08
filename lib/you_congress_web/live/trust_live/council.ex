defmodule YouCongressWeb.TrustLive.Council do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Repo, Councils, TrustRankings, PeopleLists}
  alias YouCongress.Councils.{Discovery, Invitations}
  alias YouCongress.Authors.Author

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])
    draft = own_council(socket.assigns.current_user)

    ranking =
      if YouCongress.Accounts.admin?(socket.assigns.current_user),
        do: Discovery.trust30(),
        else: %{rows: []}

    {:ok,
     socket
     |> assign(
       page_title: "My Council",
       full_width: true,
       draft: draft,
       halls: YouCongress.Halls.list_halls(),
       show_add_hall: false,
       save_error: nil,
       source_list_name: nil,
       published_list: nil,
       linked_list: nil,
       publish_fields: %{name: "", slug: ""},
       publish_slug_custom: false,
       publish_slug_error: nil,
       step: "landing",
       query: "",
       matches: [],
       people: %{},
       ranking: ranking,
       ranks: Map.new(ranking.rows, &{&1.author_id, &1}),
       dirty: false,
       last_added_id: nil,
       editing_reason: nil,
       reason_text: "",
       reason_error: nil,
       ref: nil,
       referrer: nil,
       invite_note:
         "I just picked my Council on YouCongress. I’d love to see who you’d choose — I think your picks would be worth following.",
       invite_emails: "",
       invitations: [],
       joined: 0,
       votes: [],
       counts: %{direct: 0, council: 0}
     )
     |> load_people()}
  end

  @impl true
  def handle_params(params, _, socket) do
    user = socket.assigns.current_user
    ref = params["ref"] || socket.assigns.ref
    referrer = Invitations.referrer(ref)
    default = if user, do: "mine", else: "landing"
    step = requested_step(params["step"], default)

    allowed =
      if user, do: ~w(landing pick publish invite mine votes), else: ~w(landing pick join)

    step = if step in allowed, do: step, else: default
    step = if params["statement"] && user, do: "votes", else: step
    socket = socket |> assign(step: step, ref: ref, referrer: referrer, page_title: "My Council")

    socket =
      socket
      |> assign(editing_reason: nil, reason_text: "", reason_error: nil)
      |> load_saved_view(user, step)

    socket = select_list_param(socket, params["list"])
    socket = socket |> use_list(params["use_list"]) |> add_from_link(params["add"])

    socket =
      if user do
        assign(socket,
          linked_list: PeopleLists.linked_list(user, current_list(socket.assigns.draft).id),
          counts: Discovery.vote_counts(user.author_id),
          invitations: Invitations.history(user),
          joined: Invitations.joined(user.author_id),
          votes: if(step == "votes", do: Discovery.votes(user.author_id), else: [])
        )
      else
        socket
      end

    {:noreply, load_matches(socket)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, socket |> assign(query: String.slice(q, 0, 200)) |> load_matches()}

  def handle_event("add-person", %{"id" => raw}, socket) do
    case TrustRankings.parse_id(raw) do
      nil ->
        {:noreply, socket}

      id ->
        case Repo.get(Author, id) do
          nil ->
            {:noreply, socket}

          person ->
            {:noreply,
             socket
             |> add_person(person)
             |> assign(last_added_id: person.id)
             |> push_event("council-person-added", %{id: person.id})}
        end
    end
  end

  def handle_event("remove-person", %{"id" => raw}, socket) do
    socket =
      if socket.assigns.editing_reason == TrustRankings.parse_id(raw),
        do: assign(socket, editing_reason: nil, reason_text: "", reason_error: nil),
        else: socket

    {:noreply,
     change_members(
       socket,
       Enum.reject(members(socket.assigns.draft), &(&1.author_id == TrustRankings.parse_id(raw)))
     )}
  end

  def handle_event(
        "edit-reason",
        %{"id" => raw},
        %{assigns: %{step: step}} = socket
      )
      when step in ["mine", "pick"] do
    case Enum.find(members(socket.assigns.draft), &(&1.author_id == TrustRankings.parse_id(raw))) do
      nil ->
        {:noreply, socket}

      member ->
        {:noreply,
         assign(socket,
           editing_reason: member.author_id,
           reason_text: member[:reason] || "",
           reason_error: nil
         )}
    end
  end

  def handle_event("cancel-reason", _, socket),
    do: {:noreply, assign(socket, editing_reason: nil, reason_text: "", reason_error: nil)}

  def handle_event("change-reason", %{"reason" => reason}, socket) when is_binary(reason) do
    socket = assign(socket, reason_text: reason, reason_error: nil)

    if socket.assigns.current_user && socket.assigns.editing_reason do
      if String.length(reason) <= 5_000 do
        updated =
          update_member_reason(socket.assigns.draft, socket.assigns.editing_reason, reason)

        {:noreply, change_members(socket, updated)}
      else
        {:noreply, assign(socket, reason_error: "Keep your reason under 5,000 characters.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "save-reason",
        %{"reason" => reason} = params,
        %{assigns: %{step: "pick", editing_reason: id}} = socket
      )
      when is_integer(id) and is_binary(reason) do
    if String.length(reason) <= 5_000 do
      updated =
        Enum.map(members(socket.assigns.draft), fn member ->
          if member.author_id == id, do: Map.put(member, :reason, reason), else: member
        end)

      socket = change_members(socket, updated)

      if socket.assigns.save_error do
        {:noreply, assign(socket, reason_text: reason, reason_error: socket.assigns.save_error)}
      else
        socket = assign(socket, editing_reason: nil, reason_text: "", reason_error: nil)

        if params["continue"] == "true",
          do: handle_event("save", %{}, socket),
          else: {:noreply, socket}
      end
    else
      {:noreply,
       assign(socket,
         reason_text: reason,
         reason_error: "Keep your reason under 5,000 characters."
       )}
    end
  end

  def handle_event(
        "save-reason",
        %{"reason" => reason},
        %{assigns: %{current_user: user, editing_reason: id, step: "mine"}} = socket
      )
      when not is_nil(user) and is_integer(id) and is_binary(reason) do
    list = current_list(socket.assigns.draft)

    updated =
      Enum.map(list.members, fn member ->
        if member.author_id == id, do: Map.put(member, :reason, reason), else: member
      end)

    draft = put_members(socket.assigns.draft, updated)
    socket = assign(socket, reason_text: reason)

    case Councils.save(user, draft) do
      {:ok, council} ->
        {:noreply,
         assign(socket,
           draft: with_selection(Councils.editable(council), socket.assigns.draft),
           dirty: false,
           editing_reason: nil,
           reason_text: "",
           reason_error: nil
         )}

      {:error, :stale} ->
        {:noreply,
         assign(socket,
           reason_error: "Your Council changed in another window. Reload before saving."
         )}

      _ ->
        {:noreply,
         assign(socket,
           reason_error:
             "Could not save your reason. Keep it under 5,000 characters and try again."
         )}
    end
  end

  def handle_event("reasons", %{"reasons" => reasons}, socket) do
    updated =
      Enum.map(members(socket.assigns.draft), fn m ->
        Map.put(m, :reason, Map.get(reasons, to_string(m.author_id), m[:reason]))
      end)

    {:noreply, change_members(socket, updated)}
  end

  def handle_event("save", %{"reasons" => reasons}, socket) when is_map(reasons) do
    {:noreply, socket} = handle_event("reasons", %{"reasons" => reasons}, socket)
    handle_event("save", %{}, socket)
  end

  def handle_event("save", _, %{assigns: %{current_user: nil}} = socket) do
    {:noreply, push_patch(socket, to: ~p"/council?#{%{step: "join"}}")}
  end

  def handle_event("save", _, socket) do
    case Councils.save(socket.assigns.current_user, socket.assigns.draft) do
      {:ok, council} ->
        Invitations.accept(socket.assigns.current_user, socket.assigns.ref)

        {:noreply,
         socket
         |> assign(
           draft: with_selection(Councils.editable(council), socket.assigns.draft),
           dirty: false,
           source_list_name: nil
         )
         |> push_event("clear-council-draft", %{})
         |> put_flash(:info, "Your Council is saved.")
         |> push_patch(
           to: ~p"/council?#{%{step: "publish", list: current_list(socket.assigns.draft).id}}"
         )}

      {:error, :stale} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your Council changed in another window. Reload before saving."
         )}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not save your Council. Check your picks and keep reasons under 5,000 characters."
         )}
    end
  end

  def handle_event("publish-change", params, socket) do
    {:noreply, update_publish_fields(socket, params)}
  end

  def handle_event("publish-list", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    socket = update_publish_fields(socket, params)
    {:ok, council} = Councils.ensure(user.author_id)

    selected =
      Enum.find(council.lists, &(&1.id == current_list(socket.assigns.draft).id)) ||
        Enum.find(council.lists, & &1.fallback)

    members =
      selected
      |> Map.fetch!(:members)
      |> Enum.map(&Map.take(&1, [:author_id, :reason]))

    case PeopleLists.create(
           user,
           Map.merge(socket.assigns.publish_fields, %{
             members: members,
             link_council: true,
             council_list_id: selected.id
           })
         ) do
      {:ok, list} ->
        {:noreply,
         socket
         |> assign(published_list: list)
         |> put_flash(:info, "#{list.name} is public. Your Council stays private.")
         |> push_patch(to: ~p"/council?#{%{step: "invite"}}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(publish_slug_error: YouCongressWeb.PeopleListPaths.slug_error(changeset))
         |> put_flash(:error, "Check your list name and URL before publishing.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not publish this list. Please try again.")}
    end
  end

  def handle_event("invite-change", params, socket) do
    {:noreply,
     assign(socket,
       invite_note: String.slice(params["note"] || "", 0, 2_000),
       invite_emails: params["emails"] || ""
     )}
  end

  def handle_event("invite", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    case Invitations.send(user, params["emails"] || "", params["note"] || "") do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(invitations: Invitations.history(user), invite_emails: "")
         |> put_flash(
           :info,
           if(count == 0,
             do: "These people have already been invited. No follow-ups were sent.",
             else: "#{count} invitations queued for delivery."
           )
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You can invite up to 20 people per day. Please try again tomorrow."
         )}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Enter up to 10 valid email addresses and a note under 2,000 characters."
         )}
    end
  end

  def handle_event("restore-draft", _, %{assigns: %{source_list_name: name}} = socket)
      when not is_nil(name) do
    {:noreply,
     push_event(socket, "store-council-draft", %{
       draft: socket.assigns.draft,
       ref: socket.assigns.ref
     })}
  end

  def handle_event(
        "restore-draft",
        %{"draft" => attrs} = params,
        %{assigns: %{current_user: nil}} = socket
      ) do
    case YouCongress.Councils.Draft.normalize(attrs) do
      {:ok, draft} ->
        valid =
          Discovery.people(
            Enum.flat_map(draft.lists, fn l -> Enum.map(l.members, & &1.author_id) end)
          )

        lists =
          Enum.map(draft.lists, fn l ->
            %{l | members: Enum.filter(l.members, &Map.has_key?(valid, &1.author_id))}
          end)

        socket =
          socket
          |> assign(draft: with_selection(%{draft | lists: lists}, socket.assigns.draft))
          |> load_people()

        ref = socket.assigns.ref || params["ref"]
        {:noreply, assign(socket, ref: ref, referrer: Invitations.referrer(ref))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select-topic", %{"index" => raw}, socket) do
    case Integer.parse(raw) do
      {index, ""} when index >= 0 and index < length(socket.assigns.draft.lists) ->
        socket =
          socket
          |> assign(
            draft: Map.put(socket.assigns.draft, :active_index, index),
            editing_reason: nil,
            last_added_id: nil,
            query: ""
          )
          |> load_people()
          |> load_matches()
          |> load_link()

        socket =
          if socket.assigns.current_user,
            do:
              push_patch(socket,
                to: ~p"/council?#{%{step: "pick", list: current_list(socket.assigns.draft).id}}"
              ),
            else: socket

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle-add-hall", _, socket),
    do: {:noreply, assign(socket, show_add_hall: !socket.assigns.show_add_hall)}

  def handle_event("add-hall", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    hall = Enum.find(socket.assigns.halls, &(to_string(&1.id) == params["hall_id"]))

    if hall || params["hall_id"] == "general" do
      name = String.trim(params["name"] || "")
      name = if name == "", do: if(hall, do: hall_label(hall), else: "General"), else: name
      list = %{id: nil, hall_id: hall && hall.id, name: name, fallback: false, members: []}
      lists = List.insert_at(socket.assigns.draft.lists, -2, list)
      {:noreply, save_topic_lists(socket, lists) |> assign(show_add_hall: false)}
    else
      {:noreply, put_flash(socket, :error, "Choose an existing hall or General.")}
    end
  end

  def handle_event("move-list", %{"id" => raw, "direction" => direction}, socket) do
    lists = socket.assigns.draft.lists
    index = Enum.find_index(lists, &(&1.id == TrustRankings.parse_id(raw)))
    target = if index, do: index + if(direction == "up", do: -1, else: 1)

    if index && target >= 0 && target < length(lists) - 1 && !Enum.at(lists, index).fallback do
      moved = lists |> List.delete_at(index) |> List.insert_at(target, Enum.at(lists, index))
      {:noreply, save_topic_lists(socket, moved)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-list", %{"id" => raw}, socket) do
    lists =
      Enum.reject(
        socket.assigns.draft.lists,
        &(!&1.fallback && &1.id == TrustRankings.parse_id(raw))
      )

    {:noreply, save_topic_lists(socket, lists)}
  end

  def handle_event("rename-list", %{"name" => name}, socket) do
    index = active_index(socket.assigns.draft)
    lists = List.update_at(socket.assigns.draft.lists, index, &%{&1 | name: name})
    {:noreply, save_topic_lists(socket, lists)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp update_member_reason(draft, id, reason) do
    Enum.map(members(draft), fn member ->
      if member.author_id == id, do: Map.put(member, :reason, reason), else: member
    end)
  end

  defp update_publish_fields(%{assigns: %{current_user: nil}} = socket, _params), do: socket

  defp update_publish_fields(socket, params) do
    {fields, custom?} =
      YouCongressWeb.PeopleListPaths.edit_fields(
        socket.assigns.publish_fields,
        params,
        socket.assigns.publish_slug_custom,
        socket.assigns.current_user.author_id
      )

    assign(socket, publish_fields: fields, publish_slug_custom: custom?, publish_slug_error: nil)
  end

  defp requested_step("why", _default), do: "pick"
  defp requested_step(nil, default), do: default
  defp requested_step(step, _default), do: step

  defp load_saved_view(socket, nil, _step), do: socket

  defp load_saved_view(socket, user, step) when step in ~w(mine votes publish invite),
    do:
      socket
      |> assign(draft: with_selection(own_council(user), socket.assigns.draft), dirty: false)
      |> load_people()

  defp load_saved_view(socket, _user, _step), do: socket

  defp use_list(socket, nil), do: socket

  defp use_list(socket, raw) do
    case PeopleLists.get(raw) do
      nil ->
        put_flash(socket, :error, "This public list is not available.")

      list ->
        owner = socket.assigns.current_user && socket.assigns.current_user.author_id

        members =
          list.members
          |> Enum.reject(&(&1.author_id == owner))
          |> Enum.map(&%{author_id: &1.author_id, reason: nil, source_url: nil})

        socket
        |> assign(
          draft: put_members(socket.assigns.draft, members),
          dirty: true,
          source_list_name: list.name,
          step: "pick"
        )
        |> load_people()
    end
  end

  defp add_from_link(socket, raw) do
    with id when is_integer(id) <- TrustRankings.parse_id(raw),
         %Author{} = person <- Repo.get(Author, id) do
      add_person(socket, person) |> assign(step: "pick")
    else
      _ -> socket
    end
  end

  defp own_council(nil),
    do: %{
      version: 1,
      lists: Enum.map(Councils.default_lists(), &Map.merge(&1, %{id: nil, members: []}))
    }

  defp own_council(user) do
    {:ok, council} = Councils.ensure(user.author_id)
    Councils.editable(council)
  end

  def active_index(draft),
    do: min(Map.get(draft, :active_index, length(draft.lists) - 1), length(draft.lists) - 1)

  def current_list(draft), do: Enum.at(draft.lists, active_index(draft))
  def members(draft), do: current_list(draft).members
  def hall_label(%{name: "ai-governance"}), do: "AI governance"
  def hall_label(%{name: "impact-on-jobs"}), do: "Impact on jobs"
  def hall_label(hall), do: YouCongress.Tools.StringUtils.titleize_hall(hall.name)

  defp with_selection(draft, previous),
    do: Map.put(draft, :active_index, min(active_index(previous), length(draft.lists) - 1))

  defp put_members(draft, members),
    do: %{
      draft
      | lists: List.update_at(draft.lists, active_index(draft), &%{&1 | members: members})
    }

  defp select_list_param(socket, nil), do: socket

  defp select_list_param(socket, raw) do
    index = Enum.find_index(socket.assigns.draft.lists, &(&1.id == TrustRankings.parse_id(raw)))

    if index,
      do: assign(socket, draft: Map.put(socket.assigns.draft, :active_index, index)),
      else: socket
  end

  defp load_link(socket) do
    assign(socket,
      linked_list:
        PeopleLists.linked_list(
          socket.assigns.current_user,
          current_list(socket.assigns.draft).id
        )
    )
  end

  defp save_topic_lists(socket, lists) do
    if socket.assigns.current_user do
      draft = %{socket.assigns.draft | lists: lists}

      case Councils.save(socket.assigns.current_user, draft) do
        {:ok, council} ->
          socket
          |> assign(
            draft: with_selection(Councils.editable(council), draft),
            dirty: false,
            save_error: nil
          )
          |> load_people()
          |> load_link()

        {:error, :stale} ->
          assign(socket,
            save_error: "Your Council changed in another window. Reload before continuing."
          )

        _ ->
          assign(socket,
            save_error: "Could not save. Keep a name under 120 characters and at most 20 lists."
          )
      end
    else
      socket
    end
  end

  def selected?(draft, id), do: Enum.any?(members(draft), &(&1.author_id == id))
  def pending(draft, ref), do: Jason.encode!(%{council: draft, council_ref: ref})
  def invite_url(user), do: Invitations.url(user.author_id)

  def share_href(kind, user, note) do
    text = note <> "\n\n" <> invite_url(user)

    case kind do
      :email ->
        "mailto:?" <>
          URI.encode_query(%{subject: "Who would you choose for your Council?", body: text})

      :x ->
        "https://twitter.com/intent/tweet?" <> URI.encode_query(%{text: text})

      :sms ->
        {:sms, "?" <> URI.encode_query(%{body: text})}
    end
  end

  defp add_person(socket, person) do
    owner = socket.assigns.current_user && socket.assigns.current_user.author_id

    if person.id == owner || selected?(socket.assigns.draft, person.id) do
      socket
    else
      change_members(
        socket,
        [%{author_id: person.id, reason: nil, source_url: nil} | members(socket.assigns.draft)]
      )
    end
  end

  defp change_members(socket, members) do
    draft = put_members(socket.assigns.draft, members)
    socket = socket |> assign(draft: draft, dirty: true) |> load_people()

    if socket.assigns.current_user,
      do:
        if(socket.assigns.source_list_name,
          do: socket,
          else: save_topic_lists(socket, draft.lists)
        ),
      else: push_event(socket, "store-council-draft", %{draft: draft, ref: socket.assigns.ref})
  end

  defp load_people(socket),
    do:
      assign(socket,
        people:
          Discovery.people(
            Enum.flat_map(socket.assigns.draft.lists, fn l ->
              Enum.map(l.members, & &1.author_id)
            end)
          )
      )

  defp load_matches(socket) do
    matches =
      if String.trim(socket.assigns.query) == "" do
        if YouCongress.Accounts.admin?(socket.assigns.current_user) do
          ids = Enum.map(socket.assigns.ranking.rows, & &1.author_id)
          people = Discovery.people(ids)
          Enum.map(ids, &people[&1]) |> Enum.reject(&is_nil/1)
        else
          Discovery.search("")
        end
      else
        Discovery.search(
          socket.assigns.query,
          socket.assigns.current_user && socket.assigns.current_user.author_id
        )
      end

    matches =
      if socket.assigns.current_user,
        do: Enum.reject(matches, &(&1.id == socket.assigns.current_user.author_id)),
        else: matches

    assign(socket, matches: matches)
  end
end
