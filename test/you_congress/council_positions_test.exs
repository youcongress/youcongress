defmodule YouCongress.CouncilPositionsTest do
  use YouCongress.DataCase
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  alias YouCongress.Councils
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Votes.Vote

  test "verification queries remain bounded as the number of inferred votes grows" do
    statement = statement_fixture()

    ids =
      for _ <- 1..20 do
        inferred_vote(statement.id, :verified, :verified, :verified).author_id
      end

    {small, small_queries} = measure_positions(Enum.take(ids, 1), statement.id)
    {large, large_queries} = measure_positions(ids, statement.id)
    assert map_size(small) == 1
    assert map_size(large) == 20
    assert Enum.all?(large, fn {_, position} -> position.answer == :for end)
    assert length(large_queries) == length(small_queries)
    assert Enum.count(large_queries, &String.contains?(&1, ~s("opinions_statements"))) == 1
  end

  test "batched associations preserve all eligibility rules and the statement boundary" do
    statement = statement_fixture()
    other_statement = statement_fixture()

    cases = [
      {:verified, :verified, :verified, "verified", :for},
      {:endorsed, :endorsed, :endorsed, "endorsed", :for},
      {:ai_verified, :verified, :verified, "ai_verified", :for},
      {:disputed, :verified, :verified, "disputed", nil},
      {:verified, :disputed, :verified, "disputed", nil},
      {:verified, :verified, :disputed, "disputed", nil},
      {:verified, :missing, :verified, "unverified", nil},
      {:verified, nil, :verified, "unverified", nil},
      {nil, :verified, :verified, "unverified", nil}
    ]

    expected =
      for {authenticity, relevance, answer_status, status, answer} <- cases do
        vote = inferred_vote(statement.id, authenticity, relevance, answer_status)

        Repo.insert!(%OpinionStatement{
          opinion_id: vote.opinion_id,
          statement_id: other_statement.id,
          verification_status: :disputed
        })

        {vote.author_id, status, answer}
      end

    self_cast = inferred_vote(statement.id, :disputed, :disputed, :disputed)
    self_cast |> Ecto.Changeset.change(origin: "self_cast") |> Repo.update!()
    twin = inferred_vote(statement.id, :verified, :verified, :verified)
    twin |> Ecto.Changeset.change(origin: "self_cast", twin: true) |> Repo.update!()
    no_opinion = inferred_vote(statement.id, :verified, :verified, :verified)
    no_opinion |> Ecto.Changeset.change(opinion_id: nil) |> Repo.update!()
    delegated = inferred_vote(statement.id, :verified, :verified, :verified)
    delegated |> Ecto.Changeset.change(direct: false) |> Repo.update!()
    missing = author_fixture()

    expected =
      expected ++
        [
          {self_cast.author_id, "self_cast", :for},
          {twin.author_id, "unverified", nil},
          {no_opinion.author_id, "unverified", nil}
        ]

    ids = Enum.map(expected, &elem(&1, 0)) ++ [delegated.author_id, missing.id]
    positions = Councils.positions(ids, statement.id)

    for {id, status, answer} <- expected do
      assert positions[id].status == status
      assert positions[id].answer == answer
      assert positions[id].recorded_answer == :for
    end

    refute Map.has_key?(positions, delegated.author_id)
    refute Map.has_key?(positions, missing.id)
    assert Councils.positions([], statement.id) == %{}
  end

  defp inferred_vote(statement_id, authenticity, relevance, answer_status) do
    author = author_fixture()

    opinion =
      Repo.insert!(%Opinion{
        author_id: author.id,
        content: "A sourced position",
        source_url: "https://example.com/position",
        verification_status: authenticity
      })

    if relevance != :missing do
      Repo.insert!(%OpinionStatement{
        opinion_id: opinion.id,
        statement_id: statement_id,
        verification_status: relevance
      })
    end

    Repo.insert!(%Vote{
      author_id: author.id,
      statement_id: statement_id,
      opinion_id: opinion.id,
      origin: "inferred",
      direct: true,
      answer: :for,
      verification_status: answer_status
    })
  end

  defp measure_positions(ids, statement_id) do
    key = {__MODULE__, make_ref()}
    Process.put(key, [])

    :telemetry.attach(
      key,
      [:you_congress, :repo, :query],
      &__MODULE__.record_query/4,
      {self(), key}
    )

    try do
      positions = Councils.positions(ids, statement_id)
      {positions, Process.get(key)}
    after
      :telemetry.detach(key)
      Process.delete(key)
    end
  end

  def record_query(_, _, %{query: query}, {pid, key}) do
    if self() == pid, do: Process.put(key, [query | Process.get(key, [])])
  end
end
