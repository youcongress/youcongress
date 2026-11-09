defmodule YouCongress.TrustNetwork do
  @moduledoc "Communities, independent recommendations, evidence requests, and private updates."
  import Ecto.Query
  alias YouCongress.{Repo, Councils, TrustRankings}
  alias YouCongress.Accounts.{User, Permissions}
  alias YouCongress.Halls.Hall
  alias YouCongress.TrustNetwork.{Membership, Recommendation, Request, Notification}

  def communities, do: Repo.all(from h in Hall, where: h.community_enabled, order_by: h.name)

  def memberships(author_id),
    do: Repo.all(from m in Membership, where: m.author_id == ^author_id, select: m.hall_id)

  def join(%User{} = user, hall_id) do
    with false <- Permissions.blocked?(user),
         %Hall{community_enabled: true} <- Repo.get(Hall, hall_id) do
      %Membership{}
      |> Membership.changeset(%{author_id: user.author_id, hall_id: hall_id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:hall_id, :author_id])
    else
      _ -> {:error, :forbidden}
    end
  end

  def leave(%User{} = user, hall_id),
    do:
      Repo.delete_all(
        from m in Membership, where: m.author_id == ^user.author_id and m.hall_id == ^hall_id
      )

  def configure_community(%User{role: "admin"}, hall_id, attrs) do
    Repo.get!(Hall, hall_id)
    |> Ecto.Changeset.cast(attrs, [:community_enabled, :organizer_id])
    |> Repo.update()
  end

  def configure_community(_, _, _), do: {:error, :forbidden}
  def organizer?(%User{role: "admin"}, _), do: true
  def organizer?(%User{id: id}, %Hall{organizer_id: id}), do: true
  def organizer?(_, _), do: false

  def add_statement(user, hall_id, statement_id) do
    hall = Repo.get!(Hall, hall_id)

    with true <- organizer?(user, hall),
         id when not is_nil(id) <- TrustRankings.parse_id(statement_id),
         %YouCongress.Statements.Statement{} <- Repo.get(YouCongress.Statements.Statement, id) do
      Repo.insert_all(
        YouCongress.HallsStatements.HallStatement,
        [%{hall_id: hall_id, statement_id: id, is_main: false}],
        on_conflict: :nothing
      )

      :ok
    else
      false -> {:error, :forbidden}
      _ -> {:error, :invalid_statement}
    end
  end

  def create_community_statement(user, hall_id, title) do
    hall = Repo.get!(Hall, hall_id)

    if organizer?(user, hall) do
      # The organizer's permission is restricted to this community. Preserve the
      # explicit hall association rather than scheduling a classifier to replace it.
      Repo.transaction(fn ->
        changeset =
          YouCongress.Statements.Statement.changeset(%YouCongress.Statements.Statement{}, %{
            title: title,
            user_id: user.id
          })

        case Repo.insert(changeset) do
          {:ok, statement} ->
            :ok = add_statement(user, hall_id, statement.id)
            statement

          {:error, error} ->
            Repo.rollback(error)
        end
      end)
    else
      {:error, :forbidden}
    end
  end

  def community_results(hall_id) do
    # Canonical inferred positions are evidence about a person; they are not
    # that community member's own ballot. Decisions remain a separate record.
    query =
      from m in Membership,
        join: u in User,
        on: u.author_id == m.author_id,
        join: h in Hall,
        on: h.id == m.hall_id,
        join: hs in YouCongress.HallsStatements.HallStatement,
        on: hs.hall_id == m.hall_id,
        join: s in YouCongress.Statements.Statement,
        on: s.id == hs.statement_id,
        left_join: v in YouCongress.Votes.Vote,
        on:
          v.author_id == m.author_id and v.statement_id == s.id and v.direct and
            v.origin != "inferred" and not v.twin,
        left_join: d in subquery(YouCongress.Councils.Decision.current()),
        on: d.author_id == m.author_id and d.statement_id == s.id,
        where: m.hall_id == ^hall_id and h.community_enabled,
        where: u.role not in ["spam", "blocked", "waiting_list"],
        where: not is_nil(u.email_confirmed_at) or u.signup_method in ["google", "x"],
        where: not is_nil(v.answer) or not is_nil(d.answer),
        select: %{
          statement_id: s.id,
          title: s.title,
          slug: s.slug,
          direct: not is_nil(v.answer),
          answer: fragment("COALESCE(?::text, ?)", v.answer, d.answer)
        }

    query
    |> Repo.all()
    |> Enum.frequencies()
    |> Enum.map(fn {row, count} -> Map.put(row, :count, count) end)
    |> Enum.sort_by(&{&1.title, &1.direct, &1.answer})
  end

  def recommend(%User{} = user, attrs) do
    nominee_id = TrustRankings.parse_id(Councils.value(attrs, :nominee_id))
    scope = Councils.value(attrs, :scope)

    if Permissions.blocked?(user) or nominee_id == user.author_id or
         not TrustRankings.valid_scope?(scope) do
      {:error, :invalid_recommendation}
    else
      record =
        Repo.get_by(Recommendation,
          author_id: user.author_id,
          nominee_id: nominee_id,
          scope: scope
        ) || %Recommendation{}

      record
      |> Recommendation.changeset(%{
        author_id: user.author_id,
        nominee_id: nominee_id,
        scope: scope,
        reason: Councils.value(attrs, :reason),
        source_url: Councils.value(attrs, :source_url),
        published: Councils.value(attrs, :published) || false
      })
      |> Ecto.Changeset.validate_length(:reason, max: 5_000)
      |> Ecto.Changeset.foreign_key_constraint(:nominee_id)
      |> Councils.validate_url()
      |> Repo.insert_or_update()
    end
  end

  def add_recommendation_to_council(user, recommendation) do
    Councils.add_member(user, recommendation.nominee_id)
  end

  def recommendations(author_id, public_only \\ true) do
    query =
      from r in Recommendation,
        join: a in YouCongress.Authors.Author,
        on: a.id == r.nominee_id,
        where: r.author_id == ^author_id,
        select: %{record: r, name: a.name},
        order_by: [desc: r.updated_at]

    Repo.all(if public_only, do: where(query, [r], r.published), else: query)
  end

  def delete_recommendation(%User{} = user, id),
    do:
      Repo.delete_all(
        from r in Recommendation, where: r.id == ^id and r.author_id == ^user.author_id
      )

  def request(%User{} = user, attrs) do
    if Permissions.blocked?(user) do
      {:error, :forbidden}
    else
      %Request{}
      |> Request.changeset(%{
        user_id: user.id,
        kind: Councils.value(attrs, :kind),
        body: Councils.value(attrs, :body),
        author_id: TrustRankings.parse_id(Councils.value(attrs, :author_id)),
        statement_id: TrustRankings.parse_id(Councils.value(attrs, :statement_id)),
        source_url: Councils.value(attrs, :source_url),
        status: "open"
      })
      |> Ecto.Changeset.validate_inclusion(:kind, [
        "correction",
        "missing_position",
        "missing_person"
      ])
      |> Ecto.Changeset.validate_length(:body, max: 10_000)
      |> Councils.validate_url()
      |> Ecto.Changeset.foreign_key_constraint(:author_id)
      |> Ecto.Changeset.foreign_key_constraint(:statement_id)
      |> Repo.insert()
    end
  end

  def requests(%User{role: role}) when role in ["admin", "moderator"],
    do: Repo.all(from r in Request, order_by: [desc: r.inserted_at], limit: 200)

  def requests(%User{id: id}),
    do:
      Repo.all(
        from r in Request, where: r.user_id == ^id, order_by: [desc: r.inserted_at], limit: 100
      )

  def resolve(%User{role: role}, id, status, resolution)
      when role in ["admin", "moderator"] and
             status in ["open", "reviewing", "resolved", "unresolved"] do
    request = Repo.get!(Request, id)

    result =
      request |> Request.changeset(%{status: status, resolution: resolution}) |> Repo.update()

    with {:ok, _} <- result,
         %User{} = owner <- request.user_id && Repo.get(User, request.user_id) do
      notify(
        owner.author_id,
        "request:#{id}:#{status}:#{System.unique_integer([:positive])}",
        "Your evidence request is #{status}.",
        "/council"
      )
    end

    result
  end

  def resolve(_, _, _, _), do: {:error, :forbidden}

  def notify(author_id, key, body, path) do
    %Notification{}
    |> Notification.changeset(%{author_id: author_id, key: key, body: body, path: path})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:author_id, :key])
  end

  def notifications(%User{author_id: id}),
    do:
      Repo.all(
        from n in Notification, where: n.author_id == ^id, order_by: [desc: n.id], limit: 100
      )

  def read(%User{author_id: author_id}, id),
    do:
      Repo.update_all(from(n in Notification, where: n.id == ^id and n.author_id == ^author_id),
        set: [read_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
      )

  def unread_count(%User{author_id: id}),
    do:
      Repo.aggregate(
        from(n in Notification, where: n.author_id == ^id and is_nil(n.read_at)),
        :count
      )

  def unread_count(_), do: 0

  def metrics(%User{role: "admin"}) do
    %{
      councils: Repo.aggregate(YouCongress.Councils.Council, :count),
      requests: Repo.all(from r in Request, group_by: r.status, select: {r.status, count(r.id)}),
      published:
        Repo.aggregate(from(c in YouCongress.Councils.Council, where: c.published), :count)
    }
  end
end
