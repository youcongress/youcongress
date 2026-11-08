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

  test "slugs are generated, editable, unique per owner, and reserve historical URLs" do
    user = user_fixture()
    other = user_fixture()
    {:ok, first} = PeopleLists.create(user, %{name: "People I Trust", members: []})
    assert first.slug == "people-i-trust"
    {:ok, second} = PeopleLists.create(user, %{name: first.name, members: []})
    assert second.slug == "people-i-trust-2"
    {:ok, _} = PeopleLists.create(other, %{name: "Other", slug: first.slug, members: []})

    assert {:error, changeset} =
             PeopleLists.create(user, %{name: "Duplicate", slug: first.slug, members: []})

    assert errors_on(changeset).slug

    {:ok, renamed} =
      PeopleLists.update(user, first.id, %{
        version: first.version,
        name: "Renamed",
        slug: "clear-thinkers",
        members: []
      })

    assert PeopleLists.get_by_slug(user.author_id, first.slug).id == first.id
    assert PeopleLists.get_by_slug(user.author_id, renamed.slug).id == first.id

    assert {:error, changeset} =
             PeopleLists.update(user, second.id, %{
               version: second.version,
               name: second.name,
               slug: first.slug,
               members: []
             })

    assert errors_on(changeset).slug
    assert PeopleLists.get(second.id) == second

    {:ok, reverted} =
      PeopleLists.update(user, renamed.id, %{
        version: renamed.version,
        name: "Again",
        slug: first.slug,
        members: []
      })

    assert reverted.slug == first.slug
    assert PeopleLists.get_by_slug(user.author_id, renamed.slug).id == first.id
  end

  test "invalid slugs fail without changing the list and changing only the name keeps its URL" do
    user = user_fixture()
    {:ok, list} = PeopleLists.create(user, %{name: "Original", slug: "  My-List  ", members: []})
    assert list.slug == "my-list"

    for slug <- [
          "",
          "../escape",
          "two words",
          "two--hyphens",
          "trailing-",
          String.duplicate("a", 81)
        ] do
      assert {:error, changeset} =
               PeopleLists.update(user, list.id, %{
                 version: list.version,
                 name: "Changed",
                 slug: slug,
                 members: []
               })

      assert errors_on(changeset).slug
      assert PeopleLists.get(list.id) == list
    end

    {:ok, updated} =
      PeopleLists.update(user, list.id, %{version: list.version, name: "New name", members: []})

    assert updated.slug == list.slug
  end

  test "private links require ownership, survive independent edits, and clear on deletion" do
    user = user_fixture()
    other = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(user, person.id)

    {:ok, list} =
      PeopleLists.create(user, %{
        name: "Linked",
        members: [%{author_id: person.id}],
        link_council: true
      })

    assert PeopleLists.linked_list(user).id == list.id
    assert PeopleLists.linked_list(other) == nil
    assert PeopleLists.linked_list(nil) == nil
    assert Councils.get(user.author_id) == council

    assert {:error, :forbidden} =
             PeopleLists.update(other, list.id, %{
               version: list.version,
               name: list.name,
               members: [],
               link_council: true
             })

    assert {:error, _} = PeopleLists.create(user, %{name: "", members: [], link_council: true})
    assert PeopleLists.linked_list(user).id == list.id

    {:ok, updated} =
      PeopleLists.update(user, list.id, %{
        version: list.version,
        name: "Edited independently",
        members: [%{author_id: person.id}]
      })

    assert PeopleLists.linked_list(user).id == list.id
    assert Councils.get(user.author_id) == council
    {:ok, _} = PeopleLists.delete(user, updated.id)
    assert PeopleLists.linked_list(user) == nil
    assert Councils.get(user.author_id) == council
  end
end
