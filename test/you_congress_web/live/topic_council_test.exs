defmodule YouCongressWeb.TopicCouncilTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Councils, PeopleLists}

  test "overview adds repeated topics and General, reorders them and protects the fallback", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, view, html} = live(log_in_user(conn, user), "/council")

    for name <- ["AI governance", "Impact on labor", "All statements"],
        do: assert(html =~ name)

    assert has_element?(view, "th", "Hall")
    assert has_element?(view, "th", "List to use")
    assert has_element?(view, "a", "My lists")
    refute has_element?(view, "a", "Publish a list")
    assert has_element?(view, "a", "Edit entry")
    assert has_element?(view, "details summary", "See an example")
    council = Councils.get(user.author_id)
    general = List.last(council.lists)
    refute has_element?(view, ".yc-topic-row h3")
    assert has_element?(view, "#council-hall-#{hd(council.lists).id}", "ai-governance")
    assert has_element?(view, "#topic-list-#{general.id}", "Private")
    refute has_element?(view, "#topic-list-#{general.id} button[phx-click=remove-list]")
    view |> element("button", "+ Add another hall") |> render_click()

    view
    |> form("#add-council-hall", %{hall_id: "general", name: "Inner circle"})
    |> render_submit()

    council = Councils.get(user.author_id)
    inner = Enum.find(council.lists, &(&1.name == "Inner circle"))
    assert inner.hall_id == nil
    refute inner.fallback
    for _ <- 1..3, do: render_click(view, "move-list", %{id: inner.id, direction: "up"})
    assert hd(Councils.get(user.author_id).lists).id == inner.id
    render_click(view, "move-list", %{id: general.id, direction: "up"})
    assert List.last(Councils.get(user.author_id).lists).id == general.id
    view |> element("button", "+ Add another hall") |> render_click()
    governance = Enum.find(council.lists, &(&1.name == "AI governance"))

    view |> element("#council-new-hall button", "Change hall") |> render_click()
    view |> form("#council-new-hall-choices", %{query: "ai governance"}) |> render_change()

    view
    |> element("#council-new-hall button[phx-click=choose]", "ai-governance")
    |> render_click()

    view
    |> form("#add-council-hall", %{name: "Policy inner circle"})
    |> render_submit()

    assert Enum.count(Councils.get(user.author_id).lists, &(&1.hall_id == governance.hall_id)) ==
             2

    view |> element("#topic-list-#{inner.id} button", "Remove entry") |> render_click()
    refute Enum.any?(Councils.get(user.author_id).lists, &(&1.id == inner.id))
  end

  test "entry editing shows a preview and opens the list editor with a working return link", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)
    {:ok, _} = Councils.add_member(user, person.id, topic.id)
    conn = log_in_user(conn, user)
    path = "/council?list=#{topic.id}&step=pick"
    {:ok, entry, _} = live(conn, path)
    assert has_element?(entry, "h1", "Edit Council entry")
    assert has_element?(entry, ".yc-entry-preview", person.name)
    refute has_element?(entry, "#person-search")
    refute has_element?(entry, "#council-topic-name")
    refute has_element?(entry, ".yc-steps")
    refute has_element?(entry, "button", "+ Add a reason")

    {:ok, editor, _} =
      entry |> element("a", "Edit list") |> render_click() |> follow_redirect(conn)

    assert has_element?(editor, "a[href='#{path}']", "Back to Council entry")
    editor |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()
    render_change(editor, "change", %{"reasons" => %{to_string(person.id) => "Policy expertise"}})

    {:ok, returned, _} =
      editor |> element("a", "Back to Council entry") |> render_click() |> follow_redirect(conn)

    assert has_element?(returned, "h1", "Edit Council entry")
    saved = Councils.get(user.author_id)
    assert hd(hd(saved.lists).members).reason == "Policy expertise"
    assert List.last(saved.lists).members == []
  end

  test "hall selection saves independently of the title and rejects changing final General", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    [topic, labor, general] = council.lists
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    refute has_element?(view, "#council-hall-#{topic.id} button")
    {:ok, view, _} = live(log_in_user(build_conn(), user), "/council?step=pick&list=#{topic.id}")
    selector = "#council-edit-hall-#{topic.id}"
    view |> element(selector <> " button", "Change hall") |> render_click()
    view |> form(selector <> "-choices", %{query: "impact-on-labor"}) |> render_change()
    view |> element(selector <> " button[phx-click=choose]", "impact-on-labor") |> render_click()
    updated = hd(Councils.get(user.author_id).lists)
    assert updated.name == topic.name
    assert updated.hall_id == labor.hall_id

    assert Enum.count(Councils.get(user.author_id).lists, &(&1.hall_id == labor.hall_id)) ==
             2

    refute has_element?(view, "#council-hall-#{general.id} button")
    send(view.pid, {:council_hall_selected, general.id, to_string(labor.hall_id)})
    render(view)
    assert List.last(Councils.get(user.author_id).lists).hall_id == nil

    view |> element(selector <> " button", "Change hall") |> render_click()
    view |> form(selector <> "-choices", %{query: "all statements"}) |> render_change()
    view |> element(selector <> " button[phx-click=choose]", "All statements") |> render_click()
    assert hd(Councils.get(user.author_id).lists).hall_id == nil
  end

  test "the topic editor uses own or other people's public lists without changing other topics",
       %{conn: conn} do
    user = user_fixture()
    other = user_fixture()
    first = author_fixture()
    second = author_fixture()
    third = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)

    {:ok, own} =
      PeopleLists.create(user, %{
        public: true,
        name: "My public experts",
        members: [%{author_id: first.id}]
      })

    {:ok, theirs} =
      PeopleLists.create(other, %{
        public: true,
        name: "Other public experts",
        members: [%{author_id: second.id}]
      })

    {:ok, view, _} = live(log_in_user(conn, user), "/council?step=pick&list=#{topic.id}")
    view |> element("button", "Change list") |> render_click()
    assert has_element?(view, "#public-list-option-#{own.id}")
    refute has_element?(view, "#public-list-option-#{theirs.id}")
    view |> element("#public-list-option-#{own.id} button", "Select") |> render_click()
    view |> form("#use-public-list") |> render_submit()
    assert PeopleLists.linked_list(user, topic.id).id == own.id
    assert Enum.map(hd(Councils.get(user.author_id).lists).members, & &1.author_id) == [first.id]
    render_click(view, "add-person", %{id: third.id})

    assert Enum.sort(Enum.map(PeopleLists.get(own.id).members, & &1.author_id)) ==
             Enum.sort([first.id, third.id])

    view |> element("button", "Change list") |> render_click()
    view |> form("#search-public-lists", %{scope: "all", q: "Other public"}) |> render_change()
    assert has_element?(view, "#public-list-option-#{theirs.id}", "Other public experts")
    view |> element("#public-list-option-#{theirs.id} button", "Select") |> render_click()
    refute has_element?(view, "#use-public-list input[name=link]")
    view |> form("#use-public-list", %{copy: "true"}) |> render_submit()
    updated = hd(Councils.get(user.author_id).lists)
    assert updated.name == "Other public experts (copy)"
    assert updated.hall_id == topic.hall_id
    assert Enum.map(updated.members, & &1.author_id) == [second.id]
    refute PeopleLists.linked_list(user, topic.id).public
    assert List.last(Councils.get(user.author_id).lists).members == []

    assert Enum.sort(Enum.map(PeopleLists.get(own.id).members, & &1.author_id)) ==
             Enum.sort([first.id, third.id])

    assert_redirect(
      view,
      "/lists/#{updated.people_list_id}/edit?from=council&council_list_id=#{topic.id}"
    )

    assert Enum.map(PeopleLists.get(theirs.id).members, & &1.author_id) == [second.id]
  end

  test "publishing a selected topic links that topic and keeps its connection private", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)
    {:ok, _} = Councils.add_member(user, person.id, topic.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/council?step=publish&list=#{topic.id}")
    view |> form("#publish-council-list", %{name: "Policy experts"}) |> render_submit()
    published = PeopleLists.linked_list(user, topic.id)
    assert published.name == "Policy experts"
    assert Enum.map(published.members, & &1.author_id) == [person.id]
    refute PeopleLists.linked_list(user).public
    {:ok, _, html} = live(build_conn(), YouCongressWeb.PeopleListPaths.public_path(published))
    refute html =~ "Linked to"
    refute html =~ "council_list_id"
    {:ok, overview, _} = live(log_in_user(build_conn(), user), "/council")
    assert has_element?(overview, "#topic-list-#{topic.id}", "Public")
    assert has_element?(overview, "#topic-list-#{topic.id} a", "Policy experts")
    refute has_element?(overview, "#topic-list-#{topic.id} h3")
  end

  test "following another owner's list offers a private copy and opens its editor", %{conn: conn} do
    user = user_fixture()
    owner = user_fixture()
    person = author_fixture()

    {:ok, source} =
      PeopleLists.create(owner, %{
        name: "Shared expertise",
        public: true,
        members: [%{author_id: person.id}]
      })

    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)
    {:ok, _} = PeopleLists.use_for_council(user, source.id, topic.id, council.version, false)
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/council?step=pick&list=#{topic.id}")
    assert has_element?(view, ".yc-entry-preview", person.name)
    refute has_element?(view, "a", "Edit list")

    {:ok, editor, _} =
      view |> element("button", "Make a private copy") |> render_click() |> follow_redirect(conn)

    copy = PeopleLists.linked_list(user, topic.id)
    refute copy.public
    refute copy.id == source.id
    assert has_element?(editor, "#list-person-search")
    assert has_element?(editor, "a", "Back to Council entry")
  end

  test "unavailable sources can be replaced by a new private list", %{conn: conn} do
    user = user_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)
    {:ok, _} = PeopleLists.delete(user, topic.people_list_id)
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/council?step=pick&list=#{topic.id}")
    assert has_element?(view, "#council-linked-list", "List unavailable")
    refute has_element?(view, ".yc-entry-preview")
    view |> element("button", "Choose a list") |> render_click()

    {:ok, editor, _} =
      view
      |> form("#create-council-private-list", %{name: "New private picks"})
      |> render_submit()
      |> follow_redirect(conn)

    assert has_element?(editor, "#public-list-name[value='New private picks']")
    refute PeopleLists.linked_list(user, topic.id).public
  end
end
