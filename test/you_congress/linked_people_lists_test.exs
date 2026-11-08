defmodule YouCongress.LinkedPeopleListsTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.{Councils, PeopleLists, Votes}

  defp save_council(user, members) do
    draft = Councils.get(user.author_id) |> Councils.editable()
    Councils.save(user, %{draft | lists: [%{List.last(draft.lists) | members: members}]})
  end

  test "saved memberships synchronize both ways but reasons stay separate and stale editors fail" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    {:ok, _} = Councils.add_member(user, first.id)
    {:ok, _} = save_council(user, [%{author_id: first.id, reason: "Private first"}])

    {:ok, list} =
      PeopleLists.create(user, %{
        name: "Shared",
        link_council: true,
        members: [%{author_id: first.id, reason: "Public first"}]
      })

    {:ok, council} =
      save_council(user, [
        %{author_id: first.id, reason: "Private first"},
        %{author_id: second.id, reason: "Never publish automatically"}
      ])

    updated = PeopleLists.get(list.id)

    assert Enum.map(updated.members, &{&1.author_id, &1.reason}) == [
             {first.id, "Public first"},
             {second.id, nil}
           ]

    assert updated.version == list.version + 1

    assert {:error, :stale} =
             PeopleLists.update(user, list.id, %{
               version: list.version,
               name: list.name,
               members: []
             })

    {:ok, updated} =
      PeopleLists.update(user, list.id, %{
        version: updated.version,
        name: list.name,
        members: [%{author_id: second.id, reason: "Public second"}]
      })

    assert Councils.delegate_ids(user.author_id) == [second.id]

    assert hd(List.last(Councils.get(user.author_id).lists).members).reason ==
             "Never publish automatically"

    assert {:error, :stale} = Councils.save(user, Councils.editable(council))

    {:ok, _} = save_council(user, [%{author_id: second.id, reason: "New private note"}])
    assert PeopleLists.get(list.id) == updated
    {:ok, _} = save_council(user, [])
    assert PeopleLists.get(list.id).members == []
    latest = PeopleLists.get(list.id)

    {:ok, _} =
      PeopleLists.update(user, list.id, %{
        version: latest.version,
        name: list.name,
        members: [%{author_id: first.id, reason: "Only public"}]
      })

    assert hd(List.last(Councils.get(user.author_id).lists).members).reason == nil
  end

  test "linking and editing refresh votes; unlinking stops sync and deletion keeps the Council" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: first.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: second.id, statement_id: statement.id, answer: :against})

    {:ok, list} =
      PeopleLists.create(user, %{
        name: "Voting picks",
        link_council: true,
        members: [%{author_id: first.id}]
      })

    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :for

    {:ok, list} =
      PeopleLists.update(user, list.id, %{
        version: list.version,
        name: list.name,
        members: [%{author_id: second.id}]
      })

    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :against

    {:ok, list} =
      PeopleLists.update(user, list.id, %{version: list.version, name: list.name, members: []})

    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id) == nil

    {:ok, list} =
      PeopleLists.update(user, list.id, %{
        version: list.version,
        name: list.name,
        members: [%{author_id: first.id}]
      })

    {:ok, list} =
      PeopleLists.update(user, list.id, %{
        version: list.version,
        name: list.name,
        link_council: false,
        members: []
      })

    assert Councils.delegate_ids(user.author_id) == [first.id]
    {:ok, _} = Councils.add_member(user, second.id)
    assert PeopleLists.get(list.id).members == []
    {:ok, _} = PeopleLists.delete(user, list.id)
    assert Enum.sort(Councils.delegate_ids(user.author_id)) == Enum.sort([first.id, second.id])
  end

  test "link replacement leaves old lists alone and invalid linked membership rolls back" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()

    {:ok, original} =
      PeopleLists.create(user, %{
        name: "Original",
        members: [%{author_id: first.id}],
        link_council: true
      })

    {:ok, replacement} =
      PeopleLists.create(user, %{
        name: "Replacement",
        members: [%{author_id: second.id}],
        link_council: true
      })

    assert PeopleLists.linked_list(user).id == replacement.id
    assert Councils.delegate_ids(user.author_id) == [second.id]
    assert PeopleLists.get(original.id) == original

    assert {:error, :self_in_linked_list} =
             PeopleLists.update(user, replacement.id, %{
               version: replacement.version,
               name: "Invalid",
               members: [%{author_id: user.author_id}]
             })

    assert PeopleLists.get(replacement.id) == replacement
    assert Councils.delegate_ids(user.author_id) == [second.id]
    assert PeopleLists.linked_list(user).id == replacement.id
  end
end
