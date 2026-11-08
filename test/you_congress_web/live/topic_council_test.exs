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

    for name <- ["AI governance", "Impact on jobs", "Environment", "General"],
        do: assert(html =~ name)

    council = Councils.get(user.author_id)
    general = List.last(council.lists)
    refute has_element?(view, ".yc-topic-row h3")
    assert has_element?(view, "#council-hall-#{hd(council.lists).id}", "ai-governance")
    assert has_element?(view, "#topic-list-#{general.id}", "Private list")
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

    view |> element("#topic-list-#{inner.id} button", "Remove") |> render_click()
    refute Enum.any?(Councils.get(user.author_id).lists, &(&1.id == inner.id))
  end

  test "editing one topic autosaves people and reasons without changing another topic", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    governance = hd(council.lists)
    {:ok, view, _} = live(log_in_user(conn, user), "/council?step=pick&list=#{governance.id}")
    render_click(view, "add-person", %{id: person.id})
    view |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()
    view |> form("#council-reason-#{person.id}", %{reason: "Policy expertise"}) |> render_change()
    saved = Councils.get(user.author_id)
    assert hd(hd(saved.lists).members).reason == "Policy expertise"
    assert List.last(saved.lists).members == []
    render_click(view, "select-topic", %{index: "1"})
    refute has_element?(view, "#council-member-#{person.id}")
    render_click(view, "add-person", %{id: person.id})
    saved = Councils.get(user.author_id)
    assert hd(hd(saved.lists).members).reason == "Policy expertise"
    assert hd(Enum.at(saved.lists, 1).members).reason == nil
    view |> form("form[phx-change=rename-list]", %{name: "My jobs experts"}) |> render_change()
    assert Enum.at(Councils.get(user.author_id).lists, 1).name == "My jobs experts"
  end

  test "hall selection saves independently of the title and rejects changing final General", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    [topic, _, environment, general] = council.lists
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    refute has_element?(view, "#council-hall-#{topic.id} button")
    {:ok, view, _} = live(log_in_user(build_conn(), user), "/council?step=pick&list=#{topic.id}")
    selector = "#council-edit-hall-#{topic.id}"
    view |> element(selector <> " button", "Change hall") |> render_click()
    view |> form(selector <> "-choices", %{query: "environment"}) |> render_change()
    view |> element(selector <> " button[phx-click=choose]", "environment") |> render_click()
    updated = hd(Councils.get(user.author_id).lists)
    assert updated.name == topic.name
    assert updated.hall_id == environment.hall_id

    assert Enum.count(Councils.get(user.author_id).lists, &(&1.hall_id == environment.hall_id)) ==
             2

    refute has_element?(view, "#council-hall-#{general.id} button")
    send(view.pid, {:council_hall_selected, general.id, to_string(environment.hall_id)})
    render(view)
    assert List.last(Councils.get(user.author_id).lists).hall_id == nil

    view |> element(selector <> " button", "Change hall") |> render_click()
    view |> form(selector <> "-choices", %{query: "general"}) |> render_change()
    view |> element(selector <> " button[phx-click=choose]", "General") |> render_click()
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
    view |> element("button", "Choose a list") |> render_click()
    assert has_element?(view, "#public-list-option-#{own.id}")
    refute has_element?(view, "#public-list-option-#{theirs.id}")
    view |> element("#public-list-option-#{own.id} button", "Select") |> render_click()
    view |> form("#use-public-list") |> render_submit()
    assert PeopleLists.linked_list(user, topic.id).id == own.id
    assert Enum.map(hd(Councils.get(user.author_id).lists).members, & &1.author_id) == [first.id]
    render_click(view, "add-person", %{id: third.id})

    assert Enum.sort(Enum.map(PeopleLists.get(own.id).members, & &1.author_id)) ==
             Enum.sort([first.id, third.id])

    view |> element("button", "Choose a list") |> render_click()
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

    render_click(view, "add-person", %{id: first.id})
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
    assert has_element?(overview, "#topic-list-#{topic.id}", "Public list:")
    assert has_element?(overview, "#topic-list-#{topic.id} a", "Policy experts")
    refute has_element?(overview, "#topic-list-#{topic.id} h3")
  end
end
