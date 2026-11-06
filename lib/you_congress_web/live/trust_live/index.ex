defmodule YouCongressWeb.TrustLive.Index do
  use YouCongressWeb, :live_view
  import Ecto.Query
  alias YouCongress.{Repo, TrustRankings, TrustNetwork}

  @impl true
  def mount(_params, session, socket) do
    socket = assign_current_user(socket, session["user_token"])

    {:ok,
     assign(socket,
       page_title: "Trust Network",
       scopes: TrustRankings.scopes(),
       countries: YouCongress.Countries.country_options(),
       communities: TrustNetwork.communities(),
       filters: %{},
       scope: "general",
       result: %{participants: 0, rows: []},
       comparisons: [],
       memberships: [],
       community: nil,
       community_results: [],
       recommendations: [],
       requests: [],
       updates: [],
       snapshots: TrustRankings.snapshots(),
       snapshot: nil,
       people: [],
       person_query: "",
       public_author: nil,
       admin_halls: [],
       metrics: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    scope = if TrustRankings.valid_scope?(params["scope"]), do: params["scope"], else: "general"
    filters = Map.take(params, ["community", "nominators", "nominees"])

    socket =
      assign(socket,
        scope: scope,
        filters: filters,
        result: TrustRankings.ranking(scope, filters),
        comparisons: comparison_params(params, scope)
      )

    {:noreply, load_view(socket.assigns.live_action, socket, params)}
  end

  defp load_view(:communities, socket, params), do: load_communities(socket, params)
  defp load_view(:recommendations, socket, params), do: load_recommendations(socket, params)

  defp load_view(:snapshot, socket, params),
    do: assign(socket, snapshot: TrustRankings.get_snapshot(params["id"]))

  defp load_view(:requests, %{assigns: %{current_user: user}} = socket, _) when not is_nil(user),
    do: assign(socket, requests: TrustNetwork.requests(user))

  defp load_view(:updates, %{assigns: %{current_user: user}} = socket, _) when not is_nil(user),
    do: assign(socket, updates: TrustNetwork.notifications(user))

  defp load_view(:metrics, %{assigns: %{current_user: %{role: "admin"} = user}} = socket, _),
    do: assign(socket, metrics: TrustNetwork.metrics(user))

  defp load_view(_, socket, _), do: socket

  defp comparison_params(params, scope) do
    groups =
      case params["groups"] do
        groups when is_list(groups) -> Enum.filter(groups, &is_map/1)
        _ -> [%{}, %{}]
      end

    Enum.map(Enum.take(groups, 8), fn filters ->
      %{filters: filters, result: TrustRankings.ranking(scope, filters)}
    end)
  end

  defp load_communities(socket, params) do
    user = socket.assigns.current_user

    community =
      if id = TrustRankings.parse_id(params["id"]), do: Repo.get(YouCongress.Halls.Hall, id)

    community = if community && community.community_enabled, do: community

    assign(socket,
      memberships: if(user, do: TrustNetwork.memberships(user.author_id), else: []),
      community: community,
      community_results:
        if(community, do: TrustNetwork.community_results(community.id), else: []),
      admin_halls:
        if(user && user.role == "admin",
          do: Repo.all(from h in YouCongress.Halls.Hall, order_by: h.name),
          else: []
        )
    )
  end

  defp load_recommendations(socket, params) do
    id =
      TrustRankings.parse_id(params["author_id"]) ||
        (socket.assigns.current_user && socket.assigns.current_user.author_id)

    if id do
      own = socket.assigns.current_user && socket.assigns.current_user.author_id == id

      assign(socket,
        public_author: Repo.get(YouCongress.Authors.Author, id),
        recommendations: TrustNetwork.recommendations(id, !own)
      )
    else
      socket
    end
  end

  @impl true
  def handle_event("filters", params, socket) do
    path =
      ~p"/trust/#{params["scope"] || socket.assigns.scope}?#{Map.take(params, ["community", "nominators", "nominees"])}"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("compare", params, socket) do
    groups =
      params["groups"]
      |> Enum.sort_by(fn {i, _} -> String.to_integer(i) end)
      |> Enum.map(&elem(&1, 1))

    {:noreply,
     push_patch(socket, to: ~p"/trust/compare?#{%{scope: params["scope"], groups: groups}}")}
  end

  def handle_event("add-comparison", _, socket) do
    {:noreply,
     assign(socket,
       comparisons:
         socket.assigns.comparisons ++
           [%{filters: %{}, result: TrustRankings.ranking(socket.assigns.scope)}]
     )}
  end

  def handle_event("join", %{"id" => id}, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    case TrustNetwork.join(user, id) do
      {:ok, _} ->
        {:noreply, assign(socket, memberships: TrustNetwork.memberships(user.author_id))}

      _ ->
        {:noreply, put_flash(socket, :error, "This community is not available.")}
    end
  end

  def handle_event("leave", %{"id" => id}, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    TrustNetwork.leave(user, id)
    {:noreply, assign(socket, memberships: TrustNetwork.memberships(user.author_id))}
  end

  def handle_event("enable-community", params, socket) do
    result =
      TrustNetwork.configure_community(socket.assigns.current_user, params["hall_id"], %{
        community_enabled: params["enabled"] == "true",
        organizer_id: TrustRankings.parse_id(params["organizer_id"])
      })

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket, communities: TrustNetwork.communities())
         |> put_flash(:info, "Community settings saved.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Only administrators can configure communities.")}
    end
  end

  def handle_event("add-statement", %{"statement_id" => id}, socket) do
    result =
      TrustNetwork.add_statement(
        socket.assigns.current_user,
        socket.assigns.community.id,
        TrustRankings.parse_id(id)
      )

    case result do
      :ok -> {:noreply, put_flash(socket, :info, "Statement added to the community.")}
      _ -> {:noreply, put_flash(socket, :error, "Could not add statement.")}
    end
  end

  def handle_event("create-statement", %{"title" => title}, socket) do
    case TrustNetwork.create_community_statement(
           socket.assigns.current_user,
           socket.assigns.community.id,
           title
         ) do
      {:ok, statement} ->
        {:noreply, push_navigate(socket, to: ~p"/p/#{statement.slug}")}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not create the statement. Check the title and your community permissions."
         )}
    end
  end

  def handle_event("search-people", %{"q" => q}, socket) do
    term = "%#{q}%"

    {:noreply,
     assign(socket,
       person_query: q,
       people:
         Repo.all(
           from a in YouCongress.Authors.Author,
             where: ilike(a.name, ^term),
             order_by: a.name,
             limit: 20
         )
     )}
  end

  def handle_event("recommend", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    case TrustNetwork.recommend(user, params) do
      {:ok, recommendation} ->
        if params["add_to_council"] == "true",
          do: TrustNetwork.add_recommendation_to_council(user, recommendation)

        {:noreply,
         load_recommendations(socket, %{})
         |> put_flash(
           :info,
           "Recommendation saved. Independent recommendations do not count in rankings."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Check the person, scope, and source URL.")}
    end
  end

  def handle_event(
        "delete-recommendation",
        %{"id" => id},
        %{assigns: %{current_user: user}} = socket
      )
      when not is_nil(user) do
    TrustNetwork.delete_recommendation(user, id)
    {:noreply, load_recommendations(socket, %{})}
  end

  def handle_event("request", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    case TrustNetwork.request(user, params) do
      {:ok, _} ->
        {:noreply,
         assign(socket, requests: TrustNetwork.requests(user))
         |> put_flash(:info, "Request submitted for review.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Check your request and source URL.")}
    end
  end

  def handle_event("resolve", params, socket) do
    case TrustNetwork.resolve(
           socket.assigns.current_user,
           params["request_id"],
           params["status"],
           params["resolution"]
         ) do
      {:ok, _} ->
        {:noreply, assign(socket, requests: TrustNetwork.requests(socket.assigns.current_user))}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update this request.")}
    end
  end

  def handle_event("read", %{"id" => id}, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    TrustNetwork.read(user, id)
    {:noreply, assign(socket, updates: TrustNetwork.notifications(user))}
  end

  def handle_event("snapshot", %{"title" => title}, socket) do
    case TrustRankings.snapshot(
           socket.assigns.current_user,
           socket.assigns.scope,
           socket.assigns.filters,
           title
         ) do
      {:ok, snapshot} ->
        {:noreply, push_navigate(socket, to: ~p"/trust/snapshots/#{snapshot.id}")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not publish snapshot.")}
    end
  end

  def handle_event(_, _, socket),
    do: {:noreply, put_flash(socket, :info, "Sign in to participate.")}

  def own_recommendations?(user, author), do: user && author && user.author_id == author.id
  def review?(user), do: user && user.role in ["admin", "moderator"]
  def admin?(user), do: user && user.role == "admin"
end
