defmodule YouCongress.CouncilsTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.{Councils, TrustRankings, TrustNetwork, Votes}

  test "default topic Councils preserve General and reject duplicate list IDs" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: first.id, statement_id: statement.id, answer: :against})
    vote_fixture(%{author_id: second.id, statement_id: statement.id, answer: :for})
    {:ok, _} = Councils.add_member(user, first.id)
    {:ok, council} = Councils.add_member(user, second.id)

    assert Enum.map(council.lists, & &1.name) == [
             "AI governance",
             "Impact on labor",
             "All statements"
           ]

    assert Enum.map(council.lists, fn l ->
             if l.hall_id, do: YouCongress.Halls.get_hall!(l.hall_id).name, else: nil
           end) == ["ai-governance", "impact-on-labor", nil]

    assert List.last(council.lists).fallback

    assert Councils.explain(user.author_id, statement.id).answer == nil
    attrs = Councils.editable(council)

    assert {:error, :invalid_order} =
             Councils.save(user, %{attrs | lists: attrs.lists ++ attrs.lists})

    hall = YouCongress.HallsFixtures.hall_fixture()

    assert {:error, :invalid_order} =
             Councils.save(user, %{attrs | lists: [%{hd(attrs.lists) | hall_id: hall.id}]})

    assert %{participants: 1, rows: rows} = TrustRankings.ranking("general")
    assert length(rows) == 2
    assert Enum.all?(rows, &(&1.count == 1))
  end

  test "abstention and missing members do not count toward the majority; direct abstain overrides" do
    user = user_fixture()
    voters = for _ <- 1..6, do: author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: hd(voters).id, statement_id: statement.id, answer: :for})

    vote_fixture(%{
      author_id: Enum.at(voters, 1).id,
      statement_id: statement.id,
      answer: :abstain
    })

    {:ok, council} = Councils.ensure(user.author_id)
    attrs = Councils.editable(council)

    lists =
      Enum.map(attrs.lists, fn l ->
        if l.fallback, do: %{l | members: Enum.map(voters, &%{author_id: &1.id})}, else: l
      end)

    {:ok, _} = Councils.save(user, %{attrs | lists: lists})
    assert Councils.explain(user.author_id, statement.id).answer == :for
    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :for

    {:ok, _} =
      Votes.create_or_update(%{
        user_id: user.id,
        author_id: user.author_id,
        statement_id: statement.id,
        direct: true,
        answer: :abstain
      })

    assert Councils.explain(user.author_id, statement.id).effective == :abstain
  end

  test "fallback cannot move or be removed, stale saves fail, and removal clears derived votes" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id})
    {:ok, council} = Councils.add_member(user, person.id)
    attrs = Councils.editable(council)

    assert {:error, :invalid_order} =
             Councils.save(user, %{attrs | lists: []})

    empty = Enum.map(attrs.lists, &%{&1 | members: []})
    assert {:ok, _} = Councils.save(user, %{attrs | lists: empty})
    assert {:error, :stale} = Councils.save(user, attrs)
    assert is_nil(Votes.get_by(author_id: user.author_id, statement_id: statement.id))
  end

  test "delegation does not pass through another council" do
    a = user_fixture()
    b = user_fixture()
    expert = author_fixture()
    s = statement_fixture()
    vote_fixture(%{author_id: expert.id, statement_id: s.id})
    {:ok, _} = Councils.add_member(b, expert.id)
    {:ok, _} = Councils.add_member(a, b.author_id)
    assert Councils.explain(a.author_id, s.id).answer == nil
  end

  test "standalone recommendations never count as nominations" do
    user = user_fixture()
    person = author_fixture()

    assert {:ok, _} =
             TrustNetwork.recommend(user, %{
               nominee_id: person.id,
               scope: "general",
               published: true
             })

    assert TrustRankings.ranking("general").participants == 0
  end
end
