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

    view
    |> form("#add-council-hall", %{hall_id: governance.hall_id, name: "Policy inner circle"})
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
    assert PeopleLists.linked_list(user) == nil
    {:ok, _, html} = live(build_conn(), YouCongressWeb.PeopleListPaths.public_path(published))
    refute html =~ "Linked to"
    refute html =~ "council_list_id"
  end
end
