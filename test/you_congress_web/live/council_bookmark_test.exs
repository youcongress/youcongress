defmodule YouCongressWeb.CouncilBookmarkTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  alias YouCongress.{Councils, PeopleLists}

  defp toggle(view, root, list, selected) do
    view |> form("#{root}-list-#{list.id}", %{selected: to_string(selected)}) |> render_change()
  end

  defp member?(list, person), do: Enum.any?(list.members, &(&1.author_id == person.id))

  test "adding selects All statements, and multiple lists can be selected independently",
       %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    assert view |> element(root <> " > button") |> render_click() =~ "Choose Council lists"
    assert person.id in Councils.delegate_ids(user.author_id)
    [gov, labor, all] = Councils.get(user.author_id).lists
    assert has_element?(view, root <> " label", "1. AI governance")
    assert has_element?(view, root <> " label", "2. Impact on labor")
    assert has_element?(view, root <> " label", "3. All statements")
    assert has_element?(view, "#{root}-list-#{all.id} input[checked]")
    refute has_element?(view, "#{root}-list-#{gov.id} input[checked]")
    toggle(view, root, all, false)
    toggle(view, root, gov, true)
    toggle(view, root, labor, true)

    assert Enum.map(Councils.get(user.author_id).lists, &member?(&1, person)) == [
             true,
             true,
             false
           ]

    refute has_element?(view, "#{root}-list-#{all.id} input[checked]")
    view |> element(root <> " button", "Done") |> render_click()
    refute has_element?(view, root <> " [role=dialog]")
    view |> element(root <> " > button") |> render_click()
    assert has_element?(view, "#{root}-list-#{gov.id} input[checked]")
    refute has_element?(view, "#{root}-list-#{all.id} input[checked]")
    toggle(view, root, gov, false)

    assert Enum.map(Councils.get(user.author_id).lists, &member?(&1, person)) == [
             false,
             true,
             false
           ]

    toggle(view, root, labor, false)
    refute person.id in Councils.delegate_ids(user.author_id)
    assert has_element?(view, root <> " > button", "Add to Council")
  end

  test "statement opinion cards use the picker and refresh the Council vote", %{conn: conn} do
    user = user_fixture()
    person_user = user_fixture()
    person = YouCongress.Authors.get_author!(person_user.author_id)
    statement = statement_fixture()

    opinion =
      YouCongress.OpinionsFixtures.opinion_fixture(%{
        author_id: person.id,
        user_id: person_user.id,
        statement_id: statement.id
      })

    {:ok, vote} =
      YouCongress.Votes.create_vote(person_user, %{
        statement_id: statement.id,
        author_id: person.id,
        opinion_id: opinion.id,
        answer: :for,
        direct: true,
        twin: false
      })

    {:ok, view, _} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    root = "#vote-council-#{vote.id}"
    view |> element(root <> " > button") |> render_click()
    assert person.id in Councils.delegate_ids(user.author_id)
    all = List.last(Councils.get(user.author_id).lists)
    render(view)
    assert Councils.explain(user.author_id, statement.id).answer == :for
    assert has_element?(view, root <> " [role=dialog]")
    assert has_element?(view, "#{root}-list-#{all.id} input[checked]")
    assert has_element?(view, "#statement-vote-controls", "via your Council")
  end

  test "shared source lists stay in sync while other people's lists are read-only", %{conn: conn} do
    user = user_fixture()
    owner = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    [gov, labor, all] = council.lists

    {:ok, source} =
      PeopleLists.create(owner, %{
        name: "Followed experts",
        public: true,
        members: [%{author_id: person.id}]
      })

    {:ok, council} =
      PeopleLists.use_for_council(user, source.id, labor.id, council.version, false)

    {:ok, _} =
      PeopleLists.use_for_council(user, all.people_list_id, gov.id, council.version, false)

    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    assert has_element?(view, "#{root}-list-#{labor.id} input[checked][disabled]")
    assert has_element?(view, "#{root}-list-#{gov.id}", "Same list used in 2 entries")
    toggle(view, root, gov, true)
    assert has_element?(view, "#{root}-list-#{all.id} input[checked]")
    toggle(view, root, all, false)
    refute has_element?(view, "#{root}-list-#{gov.id} input[checked]")
    assert has_element?(view, root <> " > button", "In my Council")
    render_hook(view |> element(root), "toggle-list", %{list_id: labor.id, selected: "false"})
    assert has_element?(view, root <> " [role=alert]", "only change lists you own")
    assert hd(PeopleLists.get(source.id).members).author_id == person.id
  end

  test "stale changes refresh the picker without overwriting other edits", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    {:ok, _} = Councils.save(user, Councils.editable(council))
    assert toggle(view, root, List.last(council.lists), false) =~ "changed elsewhere"
    assert person.id in Councils.delegate_ids(user.author_id)
    assert has_element?(view, "#{root}-list-#{List.last(council.lists).id} input[checked]")
  end

  test "only the last All statements entry is selected automatically", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    attrs = Councils.editable(council)
    [first | rest] = attrs.lists
    {:ok, _} = Councils.save(user, %{attrs | lists: [%{first | hall_id: nil} | rest]})
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()

    assert Enum.map(Councils.get(user.author_id).lists, &member?(&1, person)) == [
             false,
             false,
             true
           ]

    render_hook(view |> element(root), "dismiss", %{opening: 1})
    refute has_element?(view, root <> " [role=dialog]")
    view |> element(root <> " > button") |> render_click()
    render_hook(view |> element(root), "dismiss", %{opening: 1})
    assert has_element?(view, root <> " [role=dialog]")
    render_hook(view |> element(root), "dismiss", %{opening: 2})
    refute has_element?(view, root <> " [role=dialog]")
  end

  test "a read-only final list is not changed or dismissed automatically", %{conn: conn} do
    user = user_fixture()
    owner = user_fixture()
    person = author_fixture()

    {:ok, source} =
      PeopleLists.create(owner, %{name: "Public experts", public: true, members: []})

    {:ok, council} = Councils.ensure(user.author_id)

    {:ok, _} =
      PeopleLists.use_for_council(
        user,
        source.id,
        List.last(council.lists).id,
        council.version,
        false
      )

    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    assert has_element?(view, root <> " [role=alert]", "read-only or unavailable")
    refute person.id in Councils.delegate_ids(user.author_id)
    assert PeopleLists.get(source.id).members == []
    render_hook(view |> element(root), "dismiss", %{opening: 1})
    assert has_element?(view, root <> " [role=dialog]")
  end

  test "guest retains the selected person through authentication", %{conn: conn} do
    person = author_fixture()
    {:ok, view, _} = live(conn, "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    assert view |> element(root <> " > button") |> render_click() =~ "Sign in to add"
    assert has_element?(view, root <> " a[href*=pending_actions]")
  end
end
