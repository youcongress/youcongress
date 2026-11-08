defmodule YouCongress.Councils.Discovery do
  @moduledoc "Public discovery and private summaries for the single YouCongress Council."
  import Ecto.Query
  alias YouCongress.{Repo, Councils, TrustRankings}
  alias YouCongress.Councils.{PeopleList, PeopleListMember}
  alias YouCongress.Authors.Author
  alias YouCongress.Votes.Vote

  def trust30 do
    result = TrustRankings.ranking("general")
    %{result | rows: Enum.take(result.rows, 30)}
  end

  def people(ids), do: Repo.all(from a in Author, where: a.id in ^ids) |> Map.new(&{&1.id, &1})

  def search(query, owner_id \\ nil) do
    term =
      "%" <> String.replace(String.replace(String.trim(query), "%", "\\%"), "_", "\\_") <> "%"

    query =
      from a in Author, where: ilike(a.name, ^term), order_by: [asc: a.name, asc: a.id], limit: 20

    query = if owner_id, do: where(query, [a], a.id != ^owner_id), else: query
    Repo.all(query)
  end

  defp public_reason_query do
    from m in PeopleListMember,
      join: l in PeopleList,
      on: l.id == m.people_list_id,
      join: a in Author,
      on: a.id == l.author_id,
      join: u in YouCongress.Accounts.User,
      on: u.author_id == a.id,
      where: l.public,
      where: u.role not in ["spam", "blocked", "waiting_list"],
      where: not is_nil(m.reason) and fragment("btrim(?)", m.reason) != ""
  end

  def public_reason_author_ids(ids) do
    public_reason_query()
    |> where([m], m.author_id in ^ids)
    |> select([m], m.author_id)
    |> distinct(true)
    |> Repo.all()
    |> MapSet.new()
  end

  def has_public_reasons?(author_id),
    do: Repo.exists?(where(public_reason_query(), [m], m.author_id == ^author_id))

  def public_reasons(author_id) do
    public_reason_query()
    |> where([m], m.author_id == ^author_id)
    |> order_by([m], desc: m.updated_at, asc: m.id)
    |> limit(30)
    |> select([m, l, a], %{
      author: a,
      reason: m.reason,
      list_id: l.id,
      list_name: l.name,
      list_slug: l.slug
    })
    |> Repo.all()
  end

  def vote_counts(author_id) do
    counts =
      Repo.all(
        from v in Vote,
          where: v.author_id == ^author_id,
          group_by: v.direct,
          select: {v.direct, count(v.id)}
      )
      |> Map.new()

    %{direct: Map.get(counts, true, 0), council: Map.get(counts, false, 0)}
  end

  def votes(author_id) do
    Repo.all(
      from v in Vote,
        join: s in YouCongress.Statements.Statement,
        on: s.id == v.statement_id,
        where: v.author_id == ^author_id,
        order_by: [desc: v.updated_at, desc: v.id],
        limit: 50,
        select: %{statement: s, answer: v.answer, direct: v.direct}
    )
  end

  def statement_summary(statement_id, ids \\ nil) do
    ids = ids || Enum.map(trust30().rows, & &1.author_id)
    positions = Councils.positions(ids, statement_id)
    counts = Enum.frequencies_by(Map.values(positions), & &1.answer)

    %{
      total: length(ids),
      for: Map.get(counts, :for, 0),
      against: Map.get(counts, :against, 0),
      abstain: Map.get(counts, :abstain, 0),
      missing: length(ids) - Enum.count(positions, fn {_, p} -> not is_nil(p.answer) end)
    }
  end

  def statements(ids \\ nil) do
    ids = ids || Enum.map(trust30().rows, & &1.author_id)

    statements =
      Repo.all(
        from s in YouCongress.Statements.Statement,
          join: v in Vote,
          on: v.statement_id == s.id,
          where: v.author_id in ^ids and v.direct,
          group_by: s.id,
          order_by: [desc: count(v.id), desc: s.id],
          limit: 20,
          select: s
      )

    Enum.map(statements, &%{statement: &1, summary: statement_summary(&1.id, ids)})
  end
end
