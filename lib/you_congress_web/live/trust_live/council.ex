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
    default = if user && members(socket.assigns.draft) != [], do: "mine", else: "landing"
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

    socket = socket |> use_list(params["use_list"]) |> add_from_link(params["add"])

    socket =
      if user do
        assign(socket,
          linked_list: PeopleLists.linked_list(user),
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

  def handle_event("change-reason", %{"reason" => reason}, socket) when is_binary(reason),
    do: {:noreply, assign(socket, reason_text: reason, reason_error: nil)}

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

      socket =
        socket
        |> change_members(updated)
        |> assign(editing_reason: nil, reason_text: "", reason_error: nil)

      if params["continue"] == "true",
        do: handle_event("save", %{}, socket),
        else: {:noreply, socket}
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
    [list] = socket.assigns.draft.lists

    updated =
      Enum.map(list.members, fn member ->
        if member.author_id == id, do: Map.put(member, :reason, reason), else: member
      end)

    draft = %{socket.assigns.draft | lists: [%{list | members: updated}]}
    socket = assign(socket, reason_text: reason)

    case Councils.save(user, draft) do
      {:ok, council} ->
        {:noreply,
         assign(socket,
           draft: Councils.editable(council),
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
         |> assign(draft: Councils.editable(council), dirty: false, source_list_name: nil)
         |> push_event("clear-council-draft", %{})
         |> put_flash(:info, "Your Council is saved.")
         |> push_patch(to: ~p"/council?#{%{step: "publish"}}")}

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

    members =
      council.lists
      |> hd()
      |> Map.fetch!(:members)
      |> Enum.map(&Map.take(&1, [:author_id, :reason]))

    case PeopleLists.create(
           user,
           Map.merge(socket.assigns.publish_fields, %{members: members, link_council: true})
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
        valid = Discovery.people(Enum.map(members(draft), & &1.author_id))

        socket =
          change_members(
            socket,
            Enum.uniq_by(
              Enum.filter(members(draft), &Map.has_key?(valid, &1.author_id)) ++
                members(socket.assigns.draft),
              & &1.author_id
            )
          )

        ref = socket.assigns.ref || params["ref"]
        {:noreply, assign(socket, ref: ref, referrer: Invitations.referrer(ref))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

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
    do: socket |> assign(draft: own_council(user), dirty: false) |> load_people()

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

        socket |> change_members(members) |> assign(source_list_name: list.name, step: "pick")
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
      lists: [%{id: nil, name: "Council", hall_id: nil, fallback: true, members: []}]
    }

  defp own_council(user) do
    {:ok, council} = Councils.ensure(user.author_id)
    Councils.editable(council)
  end

  def members(draft), do: hd(draft.lists).members
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
    [list] = socket.assigns.draft.lists
    draft = %{socket.assigns.draft | lists: [%{list | members: members}]}
    socket = socket |> assign(draft: draft, dirty: true) |> load_people()

    if socket.assigns.current_user,
      do: socket,
      else: push_event(socket, "store-council-draft", %{draft: draft, ref: socket.assigns.ref})
  end

  defp load_people(socket),
    do:
      assign(socket,
        people: Discovery.people(Enum.map(members(socket.assigns.draft), & &1.author_id))
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
