defmodule YouCongress.CouncilDiscoveryTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.{Councils, PendingActions}
  alias YouCongress.Councils.{Discovery, Draft}

  test "Trust 30 has at most thirty people, including private nominations" do
    user = user_fixture()

    people =
      for n <- 1..31,
          do: author_fixture(%{name: "Researcher #{String.pad_leading(to_string(n), 2, "0")}"})

    {:ok, council} = Councils.ensure(user.author_id)
    attrs = Councils.editable(council)
    [list] = attrs.lists

    {:ok, _} =
      Councils.save(user, %{
        attrs
        | lists: [%{list | members: Enum.map(people, &%{author_id: &1.id})}]
      })

    result = Discovery.trust30()
    assert result.participants == 1
    assert length(result.rows) == 30
    assert Enum.all?(result.rows, &(&1.count == 1 && &1.rank == 1))
    assert hd(result.rows).name == "Researcher 01"
    assert List.last(result.rows).name == "Researcher 30"
  end

  test "guest draft merges existing picks and staged picks wait for verification" do
    user = user_fixture(%{}, nil, false)
    old = author_fixture()
    added = author_fixture()
    {:ok, _} = Councils.add_member(user, old.id)

    payload = %{
      "council" => %{
        "lists" => [%{"members" => [%{"author_id" => added.id, "reason" => "Evidence first"}]}]
      }
    }

    assert :ok = PendingActions.process(user, payload)
    assert Councils.delegate_ids(user.author_id) == [old.id]
    {:ok, user} = YouCongress.Accounts.confirm_user_email(user)
    assert :ok = PendingActions.process_staged(user)
    assert Enum.sort(Councils.delegate_ids(user.author_id)) == Enum.sort([old.id, added.id])
    refute Councils.get(user.author_id).published
  end

  test "portable old lists flatten and invalid reasons are rejected" do
    one = author_fixture()

    attrs = %{
      lists: [%{hall_id: 12, members: [%{author_id: one.id}]}, %{members: [%{author_id: one.id}]}]
    }

    assert {:ok, %{lists: [%{hall_id: nil, members: [_]}]}} = Draft.normalize(attrs)

    assert {:error, :invalid_draft} =
             Draft.normalize(%{lists: [%{members: [%{author_id: one.id, reason: %{bad: true}}]}]})
  end

  test "Trust positions separate abstentions and missing evidence" do
    people = for _ <- 1..4, do: author_fixture()
    s = statement_fixture()
    vote_fixture(%{author_id: Enum.at(people, 0).id, statement_id: s.id, answer: :for})
    vote_fixture(%{author_id: Enum.at(people, 1).id, statement_id: s.id, answer: :against})
    vote_fixture(%{author_id: Enum.at(people, 2).id, statement_id: s.id, answer: :abstain})

    assert %{total: 4, for: 1, against: 1, abstain: 1, missing: 1} =
             Discovery.statement_summary(s.id, Enum.map(people, & &1.id))
  end
end
