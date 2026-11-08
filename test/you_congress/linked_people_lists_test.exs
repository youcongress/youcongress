defmodule YouCongress.LinkedPeopleListsTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.{Councils, PeopleLists, Votes}

  defp choose_source(user, source, copy? \\ false) do
    {:ok, council} = Councils.ensure(user.author_id)

    PeopleLists.use_for_council(
      user,
      source.id,
      List.last(council.lists).id,
      council.version,
      copy?
    )
  end

  test "private lists are the same records used by Councils and reasons edit in both directions" do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(user, person.id)
    target = List.last(council.lists)
    assert PeopleLists.get(target.people_list_id) == nil
    source = PeopleLists.get(target.people_list_id, user)
    refute source.public

    {:ok, source} =
      PeopleLists.update(user, source.id, %{
        version: source.version,
        members: [%{author_id: person.id, reason: "Private reasoning"}]
      })

    updated = Councils.get(user.author_id)
    assert hd(List.last(updated.lists).members).reason == "Private reasoning"
    assert {:error, :stale} = Councils.save(user, Councils.editable(council))
    attrs = Councils.editable(updated)

    lists =
      Enum.map(attrs.lists, fn l ->
        if l.fallback,
          do: %{l | members: [%{author_id: person.id, reason: "Updated in Council"}]},
          else: l
      end)

    assert {:ok, _} = Councils.save(user, %{attrs | lists: lists})
    assert hd(PeopleLists.get(source.id, user).members).reason == "Updated in Council"

    assert {:error, :stale} =
             PeopleLists.update(user, source.id, %{version: source.version, members: []})
  end

  test "a public source is read-only for followers and changes recalculate their votes" do
    owner = user_fixture()
    follower = user_fixture()
    yes = author_fixture()
    no = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: yes.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: no.id, statement_id: statement.id, answer: :against})

    {:ok, source} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Shared experts",
        members: [%{author_id: yes.id}]
      })

    {:ok, council} = choose_source(follower, source)
    assert List.last(council.lists).people_list_id == source.id
    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer == :for
    assert {:error, :read_only_list} = Councils.add_member(follower, no.id)

    assert {:error, :forbidden} =
             PeopleLists.update(follower, source.id, %{version: source.version, members: []})

    {:ok, source} =
      PeopleLists.update(owner, source.id, %{
        version: source.version,
        members: [%{author_id: no.id}]
      })

    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer ==
             :against

    {:ok, _} = PeopleLists.update(owner, source.id, %{version: source.version, public: false})
    refute List.last(Councils.get(follower.author_id).lists).available
    assert List.last(Councils.get(follower.author_id).lists).members == []
    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id) == nil
    assert PeopleLists.get(source.id, follower) == nil
  end

  test "a private copy is independent and deleting its source marks the assignment unavailable" do
    owner = user_fixture()
    follower = user_fixture()
    person = author_fixture()

    {:ok, source} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Source",
        members: [%{author_id: person.id, reason: "Evidence"}]
      })

    {:ok, council} = choose_source(follower, source, true)
    copy_id = List.last(council.lists).people_list_id
    refute copy_id == source.id
    copy = PeopleLists.get(copy_id, follower)
    refute copy.public
    assert hd(copy.members).reason == "Evidence"
    {:ok, _} = PeopleLists.update(owner, source.id, %{version: source.version, members: []})
    assert Councils.delegate_ids(follower.author_id) == [person.id]
    {:ok, _} = PeopleLists.delete(follower, copy_id)
    assert List.last(Councils.get(follower.author_id).lists).people_list_id == nil
    refute List.last(Councils.get(follower.author_id).lists).available
  end

  test "one list may serve multiple entries without duplicated memberships" do
    user = user_fixture()
    person = author_fixture()
    {:ok, source} = PeopleLists.create(user, %{name: "Private experts", members: []})
    {:ok, council} = choose_source(user, source)

    {:ok, council} =
      PeopleLists.use_for_council(user, source.id, hd(council.lists).id, council.version, false)

    {:ok, _} = Councils.add_member(user, person.id, hd(council.lists).id)
    latest = Councils.get(user.author_id)
    assert hd(hd(latest.lists).members).author_id == person.id
    assert hd(List.last(latest.lists).members).author_id == person.id
    assert length(PeopleLists.get(source.id, user).members) == 1
  end

  test "selection rejects private sources, foreign slots, and stale Council versions" do
    owner = user_fixture()
    viewer = user_fixture()
    {:ok, private} = PeopleLists.create(owner, %{name: "Secret list", members: []})
    {:ok, public} = PeopleLists.create(owner, %{public: true, name: "Public list", members: []})
    {:ok, council} = Councils.ensure(viewer.author_id)
    {:ok, theirs} = Councils.ensure(owner.author_id)
    target = List.last(council.lists)

    assert {:error, :not_found} =
             PeopleLists.use_for_council(viewer, private.id, target.id, council.version, false)

    assert {:error, :invalid_list} =
             PeopleLists.use_for_council(
               viewer,
               public.id,
               hd(theirs.lists).id,
               council.version,
               false
             )

    assert {:error, :stale} =
             PeopleLists.use_for_council(viewer, public.id, target.id, council.version - 1, false)

    assert PeopleLists.get(private.id, viewer) == nil
    refute PeopleLists.has_public_lists?(viewer.author_id)
  end

  test "an unavailable source falls through to the next matching list" do
    owner = user_fixture()
    follower = user_fixture()
    yes = author_fixture()
    no = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: yes.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: no.id, statement_id: statement.id, answer: :against})

    {:ok, source} =
      PeopleLists.create(owner, %{
        public: true,
        name: "First choice",
        members: [%{author_id: no.id}]
      })

    {:ok, council} = Councils.add_member(follower, yes.id)
    attrs = Councils.editable(council)

    {:ok, council} =
      Councils.save(follower, %{
        attrs
        | lists: List.update_at(attrs.lists, 0, &%{&1 | hall_id: nil})
      })

    {:ok, _} =
      PeopleLists.use_for_council(
        follower,
        source.id,
        hd(council.lists).id,
        council.version,
        false
      )

    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer ==
             :against

    {:ok, _} = PeopleLists.update(owner, source.id, %{version: source.version, public: false})
    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer == :for

    {:ok, source} =
      PeopleLists.update(owner, source.id, %{version: source.version + 1, public: true})

    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer ==
             :against

    {:ok, _} = PeopleLists.delete(owner, source.id)
    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer == :for
  end

  test "merging Council owners preserves shared source lists without editing or draining them" do
    owner = user_fixture()
    duplicate = user_fixture()
    survivor = user_fixture()
    person = author_fixture()

    {:ok, source} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Shared",
        members: [%{author_id: survivor.author_id}]
      })

    {:ok, _} = choose_source(survivor, source)
    {:ok, duplicate_council} = Councils.add_member(duplicate, person.id)
    original = List.last(duplicate_council.lists).people_list_id

    assert {:ok, :ok} =
             YouCongress.Repo.transaction(fn ->
               YouCongress.Councils.Merge.merge(duplicate.author_id, survivor.author_id)
             end)

    council = Councils.get(survivor.author_id)
    assert List.last(council.lists).people_list_id == source.id
    assert List.last(council.lists).members == []
    assert hd(PeopleLists.get(source.id).members).author_id == survivor.author_id
    preserved = PeopleLists.get(original, survivor)
    assert hd(preserved.members).author_id == person.id
    assert Enum.any?(council.lists, &(&1.people_list_id == original && !&1.fallback))
  end
end
