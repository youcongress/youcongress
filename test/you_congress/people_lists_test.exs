defmodule YouCongress.PeopleListsTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{PeopleLists, Councils}
  alias YouCongress.Councils.Discovery

  test "multiple named public lists remain independent of Council membership and nominations" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    {:ok, council} = Councils.add_member(user, first.id)
    before = Discovery.trust30()

    {:ok, one} =
      PeopleLists.create(user, %{
        name: "  Thinkers  ",
        members: [%{author_id: first.id, reason: "Public reason"}]
      })

    {:ok, two} =
      PeopleLists.create(user, %{name: "Researchers", members: [%{author_id: second.id}]})

    assert one.name == "Thinkers"
    assert length(PeopleLists.for_author(user.author_id)) == 2

    assert [%{list_name: "Thinkers", reason: "Public reason"}] =
             Discovery.public_reasons(first.id)

    assert {:ok, edited} =
             PeopleLists.update(user, one.id, %{
               version: one.version,
               name: "New name",
               members: [%{author_id: second.id}]
             })

    assert edited.version == one.version + 1
    assert Discovery.public_reasons(first.id) == []
    assert {:ok, _} = PeopleLists.delete(user, two.id)
    assert Councils.get(user.author_id) == council
    assert Discovery.trust30() == before
    refute Councils.public(user.author_id)
    {:ok, _} = Councils.settings(user, %{published: true})
    refute Councils.public(user.author_id)
  end

  test "names, members, ownership, and stale writes are validated transactionally" do
    user = user_fixture()
    other = user_fixture()
    person = author_fixture()
    assert {:error, _} = PeopleLists.create(user, %{name: "  ", members: []})

    assert {:error, _} =
             PeopleLists.create(user, %{name: String.duplicate("x", 121), members: []})

    assert {:error, :invalid_members} =
             PeopleLists.create(user, %{
               name: "Duplicates",
               members: [%{author_id: person.id}, %{author_id: person.id}]
             })

    {:ok, list} =
      PeopleLists.create(user, %{
        name: "Original",
        members: [%{author_id: person.id, reason: "Kept"}]
      })

    attrs = %{name: "Changed", version: list.version, members: []}
    assert {:error, :forbidden} = PeopleLists.update(other, list.id, attrs)
    assert {:error, :forbidden} = PeopleLists.delete(other, list.id)
    assert {:error, :forbidden} = PeopleLists.delete(nil, list.id)

    assert {:error, _} =
             PeopleLists.update(user, list.id, %{
               attrs
               | members: [%{author_id: person.id, reason: String.duplicate("x", 5001)}]
             })

    assert PeopleLists.get(list.id) == list
    assert {:ok, updated} = PeopleLists.update(user, list.id, attrs)
    assert {:error, :stale} = PeopleLists.update(user, list.id, attrs)
    assert PeopleLists.get(list.id) == updated
  end
end
