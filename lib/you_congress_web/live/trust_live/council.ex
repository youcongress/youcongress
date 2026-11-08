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
    ranking = Discovery.trust30()

    {:ok,
     socket
     |> assign(
       page_title: "My Council",
       full_width: true,
       draft: draft,
       source_list_name: nil,
       published_list: nil,
       step: "landing",
       query: "",
       matches: [],
       people: %{},
       ranking: ranking,
       ranks: Map.new(ranking.rows, &{&1.author_id, &1}),
       dirty: false,
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
    step = params["step"] || default

    allowed =
      if user, do: ~w(landing pick why publish invite mine votes), else: ~w(landing pick why join)

    step = if step in allowed, do: step, else: default
    step = if params["statement"] && user, do: "votes", else: step
    socket = socket |> assign(step: step, ref: ref, referrer: referrer, page_title: "My Council")

    socket = load_saved_view(socket, user, step)

    socket = socket |> use_list(params["use_list"]) |> add_from_link(params["add"])

    socket =
      if user do
        assign(socket,
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
          nil -> {:noreply, socket}
          person -> {:noreply, add_person(socket, person)}
        end
    end
  end

  def handle_event("remove-person", %{"id" => raw}, socket) do
    {:noreply,
     change_members(
       socket,
       Enum.reject(members(socket.assigns.draft), &(&1.author_id == TrustRankings.parse_id(raw)))
     )}
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

  def handle_event("publish-list", %{"name" => name}, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    {:ok, council} = Councils.ensure(user.author_id)

    members =
      council.lists
      |> hd()
      |> Map.fetch!(:members)
      |> Enum.map(&Map.take(&1, [:author_id, :reason]))

    case PeopleLists.create(user, %{name: name, members: members}) do
      {:ok, list} ->
        {:noreply,
         socket
         |> assign(published_list: list)
         |> put_flash(:info, "#{list.name} is public. Your Council stays private.")
         |> push_patch(to: ~p"/council?#{%{step: "invite"}}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Give your list a name, up to 120 characters.")}
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
        members(socket.assigns.draft) ++ [%{author_id: person.id, reason: nil, source_url: nil}]
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
        ids = Enum.map(socket.assigns.ranking.rows, & &1.author_id)
        people = Discovery.people(ids)
        Enum.map(ids, &people[&1]) |> Enum.reject(&is_nil/1)
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
