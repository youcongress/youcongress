defmodule YouCongressWeb.TrustLive.Council do
  use YouCongressWeb, :live_view
  import YouCongressWeb.CouncilComponents
  alias YouCongress.{Repo, Councils, TrustRankings, PeopleLists}
  alias YouCongress.Councils.{Discovery, Invitations}
  alias YouCongress.Authors.Author

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     socket
     |> assign(
       page_title:
         if(socket.assigns.current_user,
           do: "My Council",
           else: "Who would you choose to oversee AI?"
         ),
       page_description:
         "Choose people you trust on AI governance and its impact on labor. Let your Council vote on your behalf, by topic. Your own vote always comes first.",
       canonical_url: url(~p"/council"),
       page_image: url(~p"/images/social-home.png"),
       page_image_alt:
         "YouCongress: people connected through their views on AI and public policy",
       page_image_width: 1731,
       page_image_height: 909,
       return_to: ~p"/council",
       full_width: true,
       draft: nil,
       halls: [],
       show_add_hall: false,
       new_hall_id: nil,
       show_public_list_picker: false,
       public_list_query: "",
       public_list_scope: "mine",
       public_list_limit: 30,
       public_list_results: [],
       selected_public_list: nil,
       save_error: nil,
       published_list: nil,
       linked_list: nil,
       list_owner: nil,
       preview_people: %{},
       linked_lists: %{},
       list_owners: %{},
       publish_fields: %{name: "", slug: ""},
       publish_slug_custom: false,
       publish_slug_error: nil,
       step: "landing",
       query: "",
       matches: [],
       people: %{},
       ranking: nil,
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
       votes: []
     )}
  end

  @impl true
  def handle_params(params, _, %{assigns: %{current_user: nil}} = socket) do
    ref = params["ref"] || socket.assigns.ref

    if params["step"] not in [nil, "landing"] || params["use_list"] || params["add"] ||
         params["list"] do
      {:noreply, redirect(socket, to: signup_path(ref))}
    else
      {:noreply, assign(socket, step: "landing", ref: ref, referrer: Invitations.referrer(ref))}
    end
  end

  def handle_params(params, _, socket) do
    user = socket.assigns.current_user
    ref = params["ref"] || socket.assigns.ref
    {:ok, council} = Councils.ensure(user.author_id)
    default = if council.onboarding_completed, do: "mine", else: "onboarding"
    step = requested_step(params["step"], default)

    allowed = ~w(landing pick people publish invite mine votes onboarding)

    step = if step in allowed, do: step, else: default
    step = if params["statement"], do: "votes", else: step

    socket =
      socket
      |> assign(
        step: step,
        ref: ref,
        referrer: nil,
        show_public_list_picker: false,
        selected_public_list: nil
      )

    socket =
      socket
      |> assign(editing_reason: nil, reason_text: "", reason_error: nil)
      |> assign_council(council)
      |> reset_step_data()

    socket =
      if step == "onboarding",
        do:
          assign(socket,
            draft:
              Map.put(socket.assigns.draft, :active_index, length(socket.assigns.draft.lists) - 1)
          ),
        else: select_list_param(socket, params["list"])

    socket = socket |> use_list(params["use_list"]) |> add_from_link(params["add"])

    {:noreply,
     socket
     |> assign(
       page_title: if(socket.assigns.step == "pick", do: "Edit Council entry", else: "My Council")
     )
     |> load_step_data()}
  end

  @impl true
  def handle_event(_event, _params, %{assigns: %{current_user: nil}} = socket),
    do: {:noreply, redirect(socket, to: signup_path(socket.assigns.ref))}

  def handle_event("finish-onboarding", _, socket) do
    if socket.assigns.save_error || socket.assigns.reason_error do
      {:noreply, put_flash(socket, :error, "Resolve the unsaved changes before continuing.")}
    else
      case Councils.complete_onboarding(socket.assigns.current_user) do
        :ok ->
          {:noreply,
           socket
           |> put_flash(:info, "Your Council is ready. You can vote directly whenever you like.")
           |> push_patch(to: ~p"/council")}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not finish. Please try again.")}
      end
    end
  end

  def handle_event("choose-people", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/council?#{%{step: "people", list: id}}")}
  end

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
      when step in ["mine", "pick", "people", "onboarding"] do
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
        %{"reason" => reason},
        %{assigns: %{step: step, editing_reason: id}} = socket
      )
      when step in ["pick", "people", "onboarding"] and is_integer(id) and is_binary(reason) do
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

        {:noreply, socket}
      end
    else
      {:noreply,
       assign(socket,
         reason_text: reason,
         reason_error: "Keep your reason under 5,000 characters."
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

    case PeopleLists.update(
           user,
           selected.people_list_id,
           Map.merge(socket.assigns.publish_fields, %{
             public: true,
             version: selected.list_version
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

  def handle_event(
        "create-private-list",
        %{"name" => name},
        %{assigns: %{current_user: user}} = socket
      )
      when not is_nil(user) do
    target = current_list(socket.assigns.draft)

    case PeopleLists.create(user, %{
           name: name,
           public: false,
           members: [],
           link_council: true,
           council_list_id: target.id
         }) do
      {:ok, source} ->
        if socket.assigns.step == "onboarding" do
          {:noreply, socket |> reload_council() |> load_people() |> load_link()}
        else
          {:noreply, push_navigate(socket, to: edit_list_path(source.id, target.id))}
        end

      _ ->
        {:noreply,
         put_flash(socket, :error, "Give the private list a name up to 120 characters.")}
    end
  end

  def handle_event("toggle-public-list-picker", _, socket) do
    {:noreply,
     socket
     |> assign(
       show_public_list_picker: !socket.assigns.show_public_list_picker,
       selected_public_list: nil
     )
     |> load_public_lists()}
  end

  def handle_event("search-public-lists", params, socket) do
    scope = if params["scope"] == "all", do: "all", else: "mine"

    {:noreply,
     socket
     |> assign(
       public_list_query: String.slice(params["q"] || "", 0, 120),
       public_list_scope: scope,
       public_list_limit: 30
     )
     |> load_public_lists()}
  end

  def handle_event("more-public-lists", _, socket),
    do:
      {:noreply,
       socket
       |> assign(public_list_limit: socket.assigns.public_list_limit + 30)
       |> load_public_lists()}

  def handle_event("preview-public-list", %{"id" => id}, socket) do
    case PeopleLists.get(id, socket.assigns.current_user) do
      nil ->
        {:noreply, put_flash(socket, :error, "This list is no longer available.")}

      list ->
        {:noreply,
         socket
         |> assign(selected_public_list: list)
         |> push_event("council-list-selected", %{})}
    end
  end

  def handle_event("copy-selected-list", _, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    socket = assign(socket, selected_public_list: socket.assigns.linked_list)
    handle_event("apply-public-list", %{"copy" => "true"}, socket)
  end

  def handle_event("apply-public-list", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    source = socket.assigns.selected_public_list
    draft = socket.assigns.draft

    if source do
      case PeopleLists.use_for_council(
             user,
             source.id,
             current_list(draft).id,
             draft.version,
             params["copy"] == "true"
           ) do
        {:ok, council} ->
          updated = with_selection(Councils.editable(council), draft)

          socket =
            socket
            |> assign(
              save_error: nil,
              selected_public_list: nil,
              show_public_list_picker: false,
              editing_reason: nil
            )
            |> assign_council(council)
            |> load_people()
            |> load_link()

          if params["copy"] == "true" && socket.assigns.step == "pick" do
            {:noreply,
             push_navigate(socket,
               to: edit_list_path(current_list(updated).people_list_id, current_list(updated).id)
             )}
          else
            {:noreply,
             put_flash(
               socket,
               :info,
               "#{source.name} is now selected. Updates to the list will apply to your Council."
             )}
          end

        {:error, :stale} ->
          {:noreply,
           assign(socket,
             save_error: "Your Council changed in another window. Reload before continuing."
           )}

        _ ->
          {:noreply, put_flash(socket, :error, "Could not use this list. Please try again.")}
      end
    else
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
      name = if name == "", do: if(hall, do: hall_label(hall), else: "All statements"), else: name
      list = %{id: nil, hall_id: hall && hall.id, name: name, fallback: false, members: []}
      lists = List.insert_at(socket.assigns.draft.lists, -2, list)
      {:noreply, save_topic_lists(socket, lists) |> assign(show_add_hall: false)}
    else
      {:noreply, put_flash(socket, :error, "Choose an existing hall or All statements.")}
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

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:council_hall_selected, list_id, raw_hall}, socket) do
    with true <- not is_nil(socket.assigns.current_user),
         true <- socket.assigns.step == "pick" || list_id == :new,
         {:ok, hall_id} <- selected_hall(socket.assigns.halls, raw_hall) do
      {:noreply, change_list_hall(socket, list_id, hall_id)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp selected_hall(_, "general"), do: {:ok, nil}

  defp selected_hall(halls, raw) do
    case Enum.find(halls, &(to_string(&1.id) == raw && &1.name != "general")) do
      nil -> :error
      hall -> {:ok, hall.id}
    end
  end

  defp change_list_hall(socket, :new, hall_id), do: assign(socket, new_hall_id: hall_id)

  defp change_list_hall(socket, list_id, hall_id) do
    lists = socket.assigns.draft.lists

    if Enum.any?(lists, &(&1.id == list_id && !&1.fallback)) do
      updated =
        Enum.map(lists, fn list ->
          if list.id == list_id, do: %{list | hall_id: hall_id}, else: list
        end)

      save_topic_lists(socket, updated)
    else
      socket
    end
  end

  defp update_member_reason(draft, id, reason) do
    Enum.map(members(draft), fn member ->
      if member.author_id == id, do: Map.put(member, :reason, reason), else: member
    end)
  end

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

  defp assign_council(socket, council) do
    links =
      council.lists
      |> Enum.filter(& &1.available)
      |> Map.new(&{&1.id, &1.people_list})

    assign(socket,
      draft: with_selection(Councils.editable(council), socket.assigns.draft),
      linked_lists: links
    )
  end

  defp reload_council(socket) do
    {:ok, council} = Councils.ensure(socket.assigns.current_user.author_id)
    assign_council(socket, council)
  end

  defp reset_step_data(socket) do
    assign(socket,
      halls: [],
      people: %{},
      matches: [],
      votes: [],
      invitations: [],
      joined: 0,
      linked_list: nil,
      list_owner: nil,
      list_owners: %{},
      preview_people: %{}
    )
  end

  defp load_step_data(%{assigns: %{step: "invite", current_user: user}} = socket),
    do:
      assign(socket,
        invitations: Invitations.history(user),
        joined: Invitations.joined(user.author_id)
      )

  defp load_step_data(%{assigns: %{step: "votes", current_user: user}} = socket),
    do: assign(socket, votes: Discovery.votes(user.author_id))

  defp load_step_data(%{assigns: %{step: "landing", ref: ref}} = socket),
    do: socket |> assign(referrer: Invitations.referrer(ref)) |> load_matches()

  defp load_step_data(socket) do
    socket =
      if socket.assigns.step in ["mine", "pick", "people"],
        do: assign(socket, halls: YouCongress.Halls.list_halls()),
        else: socket

    socket |> load_people() |> load_link() |> load_matches()
  end

  defp use_list(socket, nil), do: socket

  defp use_list(socket, raw) do
    case PeopleLists.get(raw, socket.assigns.current_user) do
      nil ->
        put_flash(socket, :error, "This public list is not available.")

      list ->
        socket
        |> assign(selected_public_list: list, show_public_list_picker: true, step: "pick")
        |> load_public_lists()
    end
  end

  defp add_from_link(socket, raw) do
    with id when is_integer(id) <- TrustRankings.parse_id(raw),
         %Author{} = person <- Repo.get(Author, id) do
      socket |> assign(step: "pick") |> add_person(person)
    else
      _ -> socket
    end
  end

  def active_index(draft),
    do: min(Map.get(draft, :active_index, length(draft.lists) - 1), length(draft.lists) - 1)

  def current_list(draft), do: Enum.at(draft.lists, active_index(draft))
  def members(draft), do: current_list(draft).members
  def hall_label(%{name: "ai-governance"}), do: "AI governance"
  def hall_label(%{name: "impact-on-labor"}), do: "Impact on labor"
  def hall_label(hall), do: YouCongress.Tools.StringUtils.titleize_hall(hall.name)

  defp with_selection(draft, nil), do: draft

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
    source = socket.assigns.linked_lists[current_list(socket.assigns.draft).id]
    socket = assign(socket, linked_list: source)

    case socket.assigns.step do
      "mine" ->
        ids = Enum.map(Map.values(socket.assigns.linked_lists), & &1.author_id)
        assign(socket, list_owners: people_by_ids(ids))

      "pick" when not is_nil(source) ->
        ids = Enum.map(Enum.take(source.members, 5), & &1.author_id)
        people = people_by_ids([source.author_id | ids])
        assign(socket, list_owner: people[source.author_id], preview_people: people)

      _ ->
        socket
    end
  end

  defp edit_list_path(source_id, entry_id),
    do: ~p"/lists/#{source_id}/edit?#{%{from: "council", council_list_id: entry_id}}"

  defp save_topic_lists(socket, lists) do
    if socket.assigns.current_user do
      draft = %{socket.assigns.draft | lists: lists}

      case Councils.save(socket.assigns.current_user, draft, refresh: :async) do
        {:ok, council} ->
          socket
          |> assign(save_error: nil)
          |> assign(draft: draft)
          |> assign_council(council)
          |> load_people()
          |> load_link()

        {:error, :read_only_list} ->
          assign(socket,
            save_error:
              "This list belongs to someone else. Make a private copy to edit its people or comments."
          )

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

  def editable_list?(_draft, nil), do: true

  def editable_list?(draft, user),
    do: current_list(draft).available && current_list(draft).list_owner_id == user.author_id

  def selected?(draft, id), do: Enum.any?(members(draft), &(&1.author_id == id))

  def signup_path(ref) do
    pending = if ref, do: Jason.encode!(%{council_ref: ref})
    YouCongressWeb.ReturnTo.sign_up_path(~p"/council", pending)
  end

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
    socket = socket |> assign(draft: draft) |> load_people()

    save_topic_lists(socket, draft.lists)
  end

  defp load_people(socket) do
    selected_members =
      case socket.assigns.step do
        "mine" -> Enum.flat_map(socket.assigns.draft.lists, &Enum.take(&1.members, 5))
        step when step in ["people", "onboarding", "publish"] -> members(socket.assigns.draft)
        _ -> []
      end

    assign(socket, people: people_by_ids(Enum.map(selected_members, & &1.author_id)))
  end

  defp people_by_ids([]), do: %{}
  defp people_by_ids(ids), do: Discovery.people(Enum.uniq(ids))

  defp load_public_lists(socket) do
    user = socket.assigns.current_user
    owner = if socket.assigns.public_list_scope == "mine", do: user && user.author_id

    results =
      if user,
        do:
          PeopleLists.search_public(socket.assigns.public_list_query,
            author_id: owner,
            viewer_id: user.author_id,
            limit: socket.assigns.public_list_limit
          ),
        else: []

    assign(socket, public_list_results: results)
  end

  defp load_matches(%{assigns: %{step: step}} = socket)
       when step in ["landing", "people", "onboarding"] do
    socket = load_ranking(socket)

    matches =
      if String.trim(socket.assigns.query) == "" do
        cond do
          socket.assigns.step == "onboarding" ->
            Discovery.most_opinions(socket.assigns.current_user.author_id)

          YouCongress.Accounts.admin?(socket.assigns.current_user) ->
            ids = Enum.map(socket.assigns.ranking.rows, & &1.author_id)
            people = Discovery.people(ids)
            Enum.map(ids, &people[&1]) |> Enum.reject(&is_nil/1)

          true ->
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

  defp load_matches(socket), do: assign(socket, matches: [])

  defp load_ranking(socket) do
    if socket.assigns.step != "onboarding" && String.trim(socket.assigns.query) == "" &&
         is_nil(socket.assigns.ranking) &&
         YouCongress.Accounts.admin?(socket.assigns.current_user),
       do: assign(socket, ranking: Discovery.trust30()),
       else: socket
  end

  def list_picker(%{state: assigns}) do
    ~H"""
    <div
      :if={@show_public_list_picker}
      id="council-public-list-picker"
      class="yc-entry-picker"
    >
      <div class="yc-between">
        <h3>{if @linked_list, do: "Change list", else: "Choose a list"}</h3>
        <button type="button" class="yc-link" phx-click="toggle-public-list-picker">
          Cancel
        </button>
      </div>
      <form
        id="search-public-lists"
        phx-change="search-public-lists"
        phx-submit="search-public-lists"
        class="space-y-3"
      >
        <label for="public-list-scope" class="yc-label">Browse</label>
        <select id="public-list-scope" name="scope" class="yc-field">
          <option value="mine" selected={@public_list_scope == "mine"}>
            My lists · Private and public
          </option>
          <option value="all" selected={@public_list_scope == "all"}>
            Everyone’s public lists
          </option>
        </select>
        <label for="public-list-search" class="yc-label">Find a list or person</label>
        <input
          id="public-list-search"
          name="q"
          value={@public_list_query}
          class="yc-field"
          placeholder="Search by list title or author"
          phx-debounce="250"
        />
      </form>
      <.selected_list_confirmation
        :if={
          @selected_public_list &&
            !Enum.any?(@public_list_results, &(&1.id == @selected_public_list.id))
        }
        selected_public_list={@selected_public_list}
      />
      <div class="yc-list yc-gap-sm">
        <div
          :for={list <- @public_list_results}
          id={"public-list-option-#{list.id}"}
          class={[
            "yc-list-item",
            @selected_public_list && @selected_public_list.id == list.id && "yc-selected-list"
          ]}
        >
          <div class="yc-between">
            <div>
              <strong>{list.name}</strong>
              <p class="yc-help">
                {list.author_name} · {people_count(list.count)} · {if list.public,
                  do: "Public",
                  else: "Private"}
              </p>
            </div>
            <button
              type="button"
              phx-click="preview-public-list"
              phx-value-id={list.id}
              class="yc-btn"
              aria-expanded={
                to_string(!!@selected_public_list && @selected_public_list.id == list.id)
              }
            >
              {if @selected_public_list && @selected_public_list.id == list.id,
                do: "Selected ✓",
                else: "Select"}
            </button>
          </div>
          <.selected_list_confirmation
            :if={@selected_public_list && @selected_public_list.id == list.id}
            selected_public_list={@selected_public_list}
          />
        </div>
        <p :if={@public_list_results == []} class="yc-list-item yc-help">
          No lists found. Try another search or browse everyone’s lists.
        </p>
      </div>
      <button
        :if={length(@public_list_results) == @public_list_limit}
        phx-click="more-public-lists"
        class="yc-link yc-gap-sm"
      >
        Show more lists
      </button>

      <form
        id="create-council-private-list"
        phx-submit="create-private-list"
        class="yc-panel yc-gap-sm"
      >
        <label for="new-private-list-name" class="yc-label">
          Or create a new private list
        </label>
        <input
          id="new-private-list-name"
          name="name"
          class="yc-field"
          required
          maxlength="120"
          placeholder="Give your list a name"
        />
        <button class="yc-btn yc-gap-sm">Create and select list</button>
      </form>
    </div>
    """
  end

  def selected_list_confirmation(assigns) do
    ~H"""
    <form
      id="use-public-list"
      phx-submit="apply-public-list"
      class="yc-panel yc-gap-sm"
    >
      <h3>Use {@selected_public_list.name}?</h3>
      <p class="yc-help">
        Uses this list for this Council entry. The hall and order stay the same. The previously selected list is kept.
      </p>
      <.link
        href={~p"/lists/#{@selected_public_list.id}"}
        target="_blank"
        rel="noopener noreferrer"
        class="yc-link"
      >
        View list ↗
      </.link>
      <p class="yc-help yc-gap-sm">
        This uses the actual list. Membership updates by its owner affect your Council. The owner cannot see who uses it.
      </p>
      <label class="block yc-gap-sm">
        <input type="checkbox" name="copy" value="true" /> Make a private copy instead
        <span class="block yc-help">
          A copy belongs to you and changes independently.
        </span>
      </label>
      <button class="yc-btn purple yc-gap-sm">Use this list</button>
    </form>
    """
  end

  def people_picker(%{state: assigns}) do
    ~H"""
    <div id="council-people-picker" class="yc-gap-sm">
      <%= if editable_list?(@draft, @current_user) do %>
        <div class={[@step != "mine" && "yc-grid", "yc-gap-sm"]}>
          <section :if={@step != "mine"}>
            <form id="person-search-form" phx-change="search" phx-submit="search">
              <label for="person-search" class="yc-label">Find a person</label>
              <input
                id="person-search"
                name="q"
                value={@query}
                class="yc-field"
                placeholder="Search by name"
                phx-debounce="250"
              />
            </form>
            <h3 class="yc-gap">
              {if @query == "", do: "People to consider", else: "Search results"}
            </h3>
            <% candidates = Enum.reject(@matches, &selected?(@draft, &1.id)) %>
            <div id="council-candidates" class="yc-list yc-gap-sm">
              <div
                :for={person <- candidates}
                id={"council-candidate-#{person.id}"}
                class="yc-list-item yc-between"
                phx-remove={
                  JS.hide(
                    transition: {"yc-picker-fade", "yc-picker-visible", "yc-picker-hidden"},
                    time: 180
                  )
                }
              >
                <.person person={person} subtitle={biography(person)} />
                <button
                  class="yc-btn"
                  phx-click="add-person"
                  phx-value-id={person.id}
                  phx-disable-with="Adding…"
                  aria-label={"Add #{person.name} to your Council"}
                >
                  + Add
                </button>
              </div>
              <p :if={candidates == []} class="yc-list-item yc-help">
                No more matches. Search for another person.
              </p>
            </div>
          </section>
          <aside class="yc-panel">
            <div class="yc-between">
              <h3>{if @step == "onboarding", do: "Your Council", else: current_list(@draft).name}</h3>
              <span class="yc-badge purple">{length(members(@draft))} selected</span>
            </div>
            <span :if={current_list(@draft).fallback} class="yc-badge yc-gap-sm">All statements</span>
            <p class="yc-help yc-gap-sm">
              {if current_list(@draft).public,
                do:
                  "This is a public list. People and reasons are public; using it in your Council stays private.",
                else: "People and reasons in this list are private."}
            </p>
            <p :if={members(@draft) == []} class="yc-help yc-gap">
              Add anyone whose judgment you value. You can change your choices anytime.
            </p>
            <div class="yc-stack yc-gap">
              <div :for={member <- members(@draft)} id={"council-member-#{member.author_id}"}>
                <div class="yc-between">
                  <.person person={@people[member.author_id]} />
                  <button
                    class="yc-link"
                    phx-click="remove-person"
                    phx-value-id={member.author_id}
                    phx-disable-with="Removing…"
                    aria-label={"Remove #{@people[member.author_id].name}"}
                  >
                    Remove
                  </button>
                </div>
                <%= if @editing_reason == member.author_id do %>
                  <form
                    id={"council-reason-#{member.author_id}"}
                    phx-change="change-reason"
                    phx-submit="save-reason"
                    class="yc-gap-sm"
                  >
                    <label for={"reason-#{member.author_id}"} class="yc-label">
                      Why do you trust {@people[member.author_id].name}?
                    </label>
                    <textarea
                      id={"reason-#{member.author_id}"}
                      name="reason"
                      class="yc-field"
                      rows="3"
                      maxlength="5000"
                      phx-debounce="blur"
                    >{@reason_text}</textarea>
                    <p :if={@reason_error} class="yc-help text-red-700" role="alert">
                      {@reason_error}
                    </p>
                    <button class="yc-link yc-gap-sm">Done</button>
                  </form>
                <% else %>
                  <p :if={member[:reason] && member.reason != ""} class="yc-help yc-gap-sm">
                    {member.reason}
                  </p>
                  <button
                    class="yc-link yc-gap-sm"
                    phx-click="edit-reason"
                    phx-value-id={member.author_id}
                  >
                    {if member[:reason] && member.reason != "",
                      do: "Edit reason",
                      else: "+ Add a reason"}
                  </button>
                <% end %>
              </div>
            </div>
            <button
              :if={@step == "mine"}
              class="yc-btn purple yc-gap"
              phx-click="choose-people"
              phx-value-id={current_list(@draft).id}
            >
              + Add people
            </button>
            <p :if={!@save_error && !@reason_error} class="yc-help yc-gap" role="status">
              ✓ All changes saved
            </p>
          </aside>
        </div>
      <% else %>
        <div class="yc-panel">
          <h3>{current_list(@draft).name}</h3>
          <p class="yc-help yc-gap-sm">
            This list follows its owner’s updates. Make a private copy to choose people yourself.
          </p>
          <div class="yc-stack yc-gap">
            <.person :for={member <- members(@draft)} person={@people[member.author_id]} />
          </div>
          <button :if={@linked_list} class="yc-btn yc-gap" phx-click="copy-selected-list">
            Make a private copy
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
