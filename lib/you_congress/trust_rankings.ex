defmodule YouCongress.TrustRankings do
  @moduledoc "Direct council nominations, deduplicated across repeated lists of the same scope."
  import Ecto.Query
  alias YouCongress.{Repo, Councils}
  alias YouCongress.Councils.{Council, List, PeopleListMember}
  alias YouCongress.Authors.Author
  alias YouCongress.Accounts.User
  alias YouCongress.TrustNetwork.{Membership, Snapshot}

  @scopes [
    {"ai-governance", "AI Governance"},
    {"ai-safety", "AI Safety"},
    {"impact-on-labor", "Impact on Jobs"},
    {"general", "General"}
  ]
  def scopes, do: @scopes
  def valid_scope?(scope), do: scope in Enum.map(@scopes, &elem(&1, 0))

  def ranking(scope, filters \\ %{}) do
    if valid_scope?(scope) do
      query =
        from c in Council,
          as: :council,
          join: l in List,
          on: l.council_id == c.id,
          join: m in PeopleListMember,
          on: m.people_list_id == l.people_list_id,
          join: participant in Author,
          on: participant.id == c.author_id,
          join: user in User,
          on: user.author_id == participant.id,
          join: nominee in Author,
          on: nominee.id == m.author_id,
          left_join: h in YouCongress.Halls.Hall,
          on: h.id == l.hall_id,
          where: m.author_id != c.author_id,
          where:
            l.people_list_id in subquery(
              from p in YouCongress.Councils.PeopleList,
                where: p.public or p.author_id == parent_as(:council).author_id,
                select: p.id
            ),
          where: user.role not in ["spam", "blocked", "waiting_list"],
          where: not is_nil(user.email_confirmed_at) or user.signup_method in ["google", "x"],
          select: %{
            participant_id: participant.id,
            participant_country: participant.country_id,
            nominee_id: nominee.id,
            nominee_country: nominee.country_id,
            name: nominee.name,
            image: nominee.profile_image_url,
            hall: h.name,
            hall_id: l.hall_id
          }

      query =
        if scope == "general",
          do: where(query, [c, l], is_nil(l.hall_id)),
          else: where(query, [c, l, m, p, u, n, h], h.name == ^scope)

      community = parse_id(filters["community"])

      query =
        if community,
          do:
            where(
              query,
              [c],
              c.author_id in subquery(
                from cm in Membership,
                  join: hall in YouCongress.Halls.Hall,
                  on: hall.id == cm.hall_id,
                  where: cm.hall_id == ^community and hall.community_enabled,
                  select: cm.author_id
              )
            ),
          else: query

      nominations =
        Repo.all(query)
        |> Enum.filter(&country_matches?(&1.participant_country, filters["nominators"]))
        |> Enum.uniq_by(&{&1.participant_id, &1.nominee_id})

      denominator = nominations |> Enum.map(& &1.participant_id) |> Enum.uniq() |> length()

      rows =
        nominations
        |> Enum.filter(&country_matches?(&1.nominee_country, filters["nominees"]))
        |> Enum.group_by(& &1.nominee_id)
        |> Enum.map(fn {id, entries} ->
          entry = hd(entries)

          %{
            author_id: id,
            name: entry.name || "Participant",
            image: entry.image,
            count: length(entries),
            share:
              if(denominator == 0,
                do: 0.0,
                else: Float.round(100 * length(entries) / denominator, 2)
              )
          }
        end)
        |> Enum.sort_by(&{-&1.count, &1.name, &1.author_id})

      rows =
        Enum.with_index(rows, 1)
        |> Enum.map(fn {row, _index} ->
          Map.put(row, :rank, 1 + Enum.count(rows, &(&1.count > row.count)))
        end)

      %{scope: scope, participants: denominator, rows: rows}
    else
      %{scope: scope, participants: 0, rows: []}
    end
  end

  defp country_matches?(_, value) when value in [nil, "", "all"], do: true
  defp country_matches?(country, "unknown"), do: is_nil(country)
  defp country_matches?(country, value), do: country == parse_id(value)
  def parse_id(value) when is_integer(value) and value > 0, do: value

  def parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  def parse_id(_), do: nil

  def snapshot(%User{role: "admin"} = user, scope, filters, title) do
    result = ranking(scope, filters) |> Jason.encode!() |> Jason.decode!()

    %Snapshot{}
    |> Snapshot.changeset(%{
      scope: scope,
      filters: filters,
      title: title,
      result: result,
      user_id: user.id
    })
    |> Repo.insert()
  end

  def snapshot(_, _, _, _), do: {:error, :forbidden}
  def snapshots, do: Repo.all(from s in Snapshot, order_by: [desc: s.inserted_at])
  def get_snapshot(id), do: Repo.get(Snapshot, id)

  def backfill do
    ids =
      Repo.all(
        from d in YouCongress.Delegations.Delegation, select: d.deleguee_id, distinct: true
      )

    Enum.each(ids, fn id ->
      {:ok, _} = Councils.ensure(id)
      YouCongress.DelegationVotes.update_author_delegated_votes(id)
    end)

    length(ids)
  end
end
