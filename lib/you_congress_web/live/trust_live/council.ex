defmodule YouCongressWeb.TrustLive.Council do
  use YouCongressWeb, :live_view
  import Ecto.Query
  alias YouCongress.{Repo, Councils, TrustRankings}
  alias YouCongress.Authors.Author
  alias YouCongress.Statements.Statement

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {draft, settings} =
      if socket.assigns.current_user do
        {:ok, council} = Councils.ensure(socket.assigns.current_user.author_id)
        {Councils.editable(council), council}
      else
        {%{
           version: 1,
           lists: Enum.map(Councils.default_lists(), &Map.merge(&1, %{id: nil, members: []}))
         }, %{published: false, digest: "off"}}
      end

    {:ok,
     socket
     |> assign(
       page_title: "Your AI council",
       draft: draft,
       settings: settings,
       people: %{},
       matches: [],
       active_list: 0,
       query: "",
       hall_query: "",
       hall_matches: [],
       statement: nil,
       comparison_statements: [],
       matrix: [],
       understanding: nil,
       explanation: nil,
       statements: [],
       statement_query: "",
       selected_person: nil,
       readonly: false,
       public_author: nil,
       dirty: false
     )
     |> load_people()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      case params do
        %{"author_id" => id} ->
          case Councils.public(id) do
            nil ->
              socket
              |> put_flash(:error, "This council is not public.")
              |> push_navigate(to: ~p"/council")

            council ->
              assign(socket,
                draft: Councils.editable(council),
                readonly: true,
                public_author: Repo.get!(Author, id),
                settings: council
              )
              |> load_people()
          end

        _ ->
          socket
      end

    person = TrustRankings.parse_id(params["add"])

    socket =
      if person, do: assign(socket, selected_person: Repo.get(Author, person)), else: socket

    socket =
      case TrustRankings.parse_id(params["statement"]) do
        nil ->
          socket

        id ->
          assign(socket,
            statement: Repo.get(Statement, id),
            comparison_statements: [Repo.get(Statement, id)]
          )
          |> preview()
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => q, "list" => index}, socket) do
    term = "%#{q}%"

    matches =
      if String.trim(q) == "",
        do: [],
        else: Repo.all(from a in Author, where: ilike(a.name, ^term), order_by: a.name, limit: 15)

    {:noreply, assign(socket, matches: matches, query: q, active_list: index(index))}
  end

  def handle_event("search-halls", %{"q" => q}, socket) do
    term = "%#{q}%"

    halls =
      Repo.all(
        from h in YouCongress.Halls.Hall, where: ilike(h.name, ^term), order_by: h.name, limit: 20
      )

    {:noreply, assign(socket, hall_query: q, hall_matches: halls)}
  end

  def handle_event("add-list", params, socket) do
    hall =
      case TrustRankings.parse_id(params["hall"]) do
        nil -> nil
        id -> Repo.get(YouCongress.Halls.Hall, id)
      end

    list = %{
      id: nil,
      hall_id: hall && hall.id,
      name: if(hall, do: hall.name, else: "General"),
      fallback: false,
      members: []
    }

    lists = List.insert_at(socket.assigns.draft.lists, -2, list)
    change(socket, lists)
  end

  def handle_event("move", %{"index" => i, "direction" => direction}, socket) do
    i = index(i)
    lists = socket.assigns.draft.lists
    target = i + if(direction == "up", do: -1, else: 1)

    if i < length(lists) - 1 and target >= 0 and target < length(lists) - 1 do
      item = Enum.at(lists, i)
      change(socket, lists |> List.delete_at(i) |> List.insert_at(target, item))
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove-list", %{"index" => i}, socket) do
    i = index(i)

    if i < length(socket.assigns.draft.lists) - 1,
      do: change(socket, List.delete_at(socket.assigns.draft.lists, i)),
      else: {:noreply, socket}
  end

  def handle_event("rename", %{"index" => i, "name" => name}, socket) do
    change(socket, List.update_at(socket.assigns.draft.lists, index(i), &%{&1 | name: name}))
  end

  def handle_event("add-person", %{"id" => id, "list" => i}, socket) do
    id = TrustRankings.parse_id(id)

    if id && Repo.get(Author, id) &&
         (!socket.assigns.current_user || id != socket.assigns.current_user.author_id) do
      lists =
        List.update_at(socket.assigns.draft.lists, index(i), fn list ->
          if Enum.any?(list.members, &(&1.author_id == id)),
            do: list,
            else: %{
              list
              | members: list.members ++ [%{author_id: id, reason: nil, source_url: nil}]
            }
        end)

      change(assign(socket, selected_person: nil), lists)
    else
      {:noreply, put_flash(socket, :error, "Choose another person.")}
    end
  end

  def handle_event("remove-person", %{"id" => id, "list" => i}, socket) do
    lists =
      List.update_at(socket.assigns.draft.lists, index(i), fn l ->
        %{l | members: Enum.reject(l.members, &(&1.author_id == TrustRankings.parse_id(id)))}
      end)

    change(socket, lists)
  end

  def handle_event(
        "reason",
        %{"person_id" => id, "list" => i, "reason" => reason},
        socket
      ) do
    lists =
      List.update_at(socket.assigns.draft.lists, index(i), fn l ->
        %{
          l
          | members:
              Enum.map(l.members, fn m ->
                if m.author_id == TrustRankings.parse_id(id),
                  do: Map.put(m, :reason, reason),
                  else: m
              end)
        }
      end)

    change(socket, lists)
  end

  def handle_event("save", _, %{assigns: %{readonly: true}} = socket), do: {:noreply, socket}

  def handle_event("save", _, %{assigns: %{current_user: nil}} = socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :info,
         "Sign in below to save your council and include your nominations."
       )}

  def handle_event("save", _, socket) do
    case Councils.save(socket.assigns.current_user, socket.assigns.draft) do
      {:ok, council} ->
        {:noreply,
         socket
         |> assign(draft: Councils.editable(council), dirty: false)
         |> preview()
         |> put_flash(
           :info,
           "Council saved. Your nominations are included in global and joined-community rankings."
         )}

      {:error, :stale} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your council changed in another window. Reload before saving."
         )}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Check list names, people, and source links before saving.")}
    end
  end

  def handle_event(
        "settings",
        params,
        %{assigns: %{current_user: user, readonly: false}} = socket
      )
      when not is_nil(user) do
    attrs = %{published: params["published"] == "true", digest: params["digest"] || "off"}

    case Councils.settings(user, attrs) do
      {:ok, settings} ->
        {:noreply,
         assign(socket, settings: settings)
         |> put_flash(:info, "Sharing and update preferences saved.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not save preferences.")}
    end
  end

  def handle_event("search-statements", %{"q" => q}, socket) do
    term = "%#{q}%"

    statements =
      Repo.all(
        from s in Statement, where: ilike(s.title, ^term), order_by: [desc: s.id], limit: 10
      )

    {:noreply, assign(socket, statements: statements, statement_query: q)}
  end

  def handle_event("inspect", %{"id" => id}, socket) do
    statement = Repo.get!(Statement, id)
    YouCongress.Track.event("Council evidence inspected", socket.assigns.current_user)
    statements = Enum.uniq_by(socket.assigns.comparison_statements ++ [statement], & &1.id)

    {:noreply,
     assign(socket, statement: statement, comparison_statements: statements) |> preview()}
  end

  def handle_event("remove-comparison", %{"id" => id}, socket) do
    statements = Enum.reject(socket.assigns.comparison_statements, &(to_string(&1.id) == id))
    {:noreply, assign(socket, comparison_statements: statements) |> preview()}
  end

  def handle_event("understanding", %{"answer" => answer}, socket) do
    correct = answer == "direct"

    YouCongress.Track.event(
      if(correct,
        do: "Delegation understanding correct",
        else: "Delegation understanding needs explanation"
      ),
      socket.assigns.current_user
    )

    {:noreply, assign(socket, understanding: correct)}
  end

  def handle_event(
        "restore-draft",
        %{"draft" => attrs},
        %{assigns: %{current_user: nil}} = socket
      ) do
    case YouCongress.Councils.Draft.normalize(attrs) do
      {:ok, draft} -> change(socket, draft.lists)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("copy", _, %{assigns: %{readonly: true}} = socket) do
    lists = Enum.map(socket.assigns.draft.lists, &%{&1 | id: nil})

    if socket.assigns.current_user do
      {:ok, council} = Councils.ensure(socket.assigns.current_user.author_id)
      fallback = Enum.find(council.lists, & &1.fallback)
      lists = List.update_at(lists, -1, &%{&1 | id: fallback.id})

      {:noreply,
       socket
       |> assign(
         readonly: false,
         public_author: nil,
         draft: %{version: council.version, lists: lists},
         settings: council,
         dirty: true
       )
       |> put_flash(
         :info,
         "Copied to a draft. Review before saving; this replaces your current lists."
       )}
    else
      change(assign(socket, readonly: false, public_author: nil), lists)
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp index(value) do
    case Integer.parse(to_string(value)) do
      {i, ""} when i >= 0 -> i
      _ -> 0
    end
  end

  defp change(%{assigns: %{readonly: true}} = socket, _), do: {:noreply, socket}

  defp change(socket, lists) do
    socket =
      socket
      |> assign(draft: %{socket.assigns.draft | lists: lists}, dirty: true)
      |> load_people()
      |> preview()

    socket =
      if socket.assigns.current_user,
        do: socket,
        else: push_event(socket, "store-council-draft", %{draft: socket.assigns.draft})

    {:noreply, socket}
  end

  defp load_people(socket) do
    ids =
      socket.assigns.draft.lists
      |> Enum.flat_map(&Enum.map(&1.members, fn m -> m.author_id end))
      |> Enum.uniq()

    assign(socket, people: Map.new(Repo.all(from a in Author, where: a.id in ^ids), &{&1.id, &1}))
  end

  defp preview(%{assigns: %{statement: nil}} = socket), do: socket

  defp preview(socket) do
    ids = Map.keys(socket.assigns.people)

    explanation =
      YouCongress.Councils.Evaluator.evaluate(
        socket.assigns.draft.lists,
        Councils.positions(ids, socket.assigns.statement.id)
      )

    matrix =
      Enum.map(socket.assigns.comparison_statements, fn statement ->
        positions = Councils.positions(ids, statement.id)
        result = YouCongress.Councils.Evaluator.evaluate(socket.assigns.draft.lists, positions)

        own =
          if socket.assigns.current_user,
            do: Councils.explain(socket.assigns.current_user.author_id, statement.id).effective

        %{statement: statement, positions: positions, result: result.answer, own: own}
      end)

    assign(socket, explanation: explanation, matrix: matrix)
  end

  def person_name(people, id) do
    case people[id] do
      nil -> "Unavailable person"
      person -> person.name || "Participant"
    end
  end

  def answer(nil), do: "No position"
  def answer(value), do: value |> to_string() |> String.capitalize()
  def pending(draft), do: Jason.encode!(%{council: draft})
end
