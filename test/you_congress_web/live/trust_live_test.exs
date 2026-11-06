defmodule YouCongressWeb.TrustLiveTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Councils, TrustNetwork, TrustRankings}

  test "guest can draft repeated General lists and compare", %{conn: conn} do
    {:ok, view, html} = live(conn, "/council")
    assert html =~ "Build your AI council"
    render_click(view, "add-list", %{})
    render_click(view, "add-list", %{})

    assert length(Floki.find(Floki.parse_document!(render(view)), "section[id^=council-list]")) ==
             5

    assert render_click(view, "save") =~ "Sign in below"
    {:ok, _, _} = live(conn, "/trust/compare")
  end

  test "owner saves more than five people and publishes repeated lists", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    people = for _ <- 1..6, do: author_fixture()
    {:ok, view, _} = live(conn, "/council")
    render_click(view, "add-list", %{})

    for person <- people,
        do: render_click(view, "add-person", %{"id" => to_string(person.id), "list" => "2"})

    render_click(view, "move", %{"index" => "2", "direction" => "up"})
    render_click(view, "move", %{"index" => "1", "direction" => "up"})
    assert render_click(view, "save") =~ "Council saved"
    council = Councils.get(user.author_id)
    assert length(hd(council.lists).members) == 6
    assert List.last(council.lists).fallback
    render_submit(view, "settings", %{"published" => "true", "digest" => "weekly"})
    assert Councils.public(user.author_id)
    {:ok, public, html} = live(conn, "/a/#{user.author_id}/council")
    assert html =~ "Copy into my draft"
    refute has_element?(public, "#save-council")
    assert render_click(public, "save") =~ "Copy into my draft"
  end

  test "private councils do not expose selections", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, _} = Councils.add_member(user, person.id)

    assert {:error, {:live_redirect, %{to: "/council"}}} =
             live(conn, "/a/#{user.author_id}/council")
  end

  test "rankings and exports show saved nominations", %{conn: conn} do
    user = user_fixture()
    person = author_fixture(%{name: "Trusted Person"})
    {:ok, _} = Councils.add_member(user, person.id)
    {:ok, _, html} = live(conn, "/trust/general")
    assert html =~ "Trusted Person"
    assert html =~ "100.0%"
    response = conn |> get("/trust/general/export.csv") |> response(200)
    assert response =~ "Trusted Person"
    assert response =~ "Participants"
    {:ok, snapshot} = TrustRankings.snapshot(admin_fixture(), "general", %{}, "Test snapshot")
    {:ok, _, html} = live(conn, "/trust/snapshots/#{snapshot.id}")
    assert html =~ "Historical snapshot"
  end

  test "join and leave communities; review requests and private updates", %{conn: conn} do
    admin = admin_fixture()
    user = user_fixture()
    hall = YouCongress.HallsFixtures.hall_fixture()
    {:ok, _} = TrustNetwork.configure_community(admin, hall.id, %{community_enabled: true})
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/communities")
    render_click(view, "join", %{"id" => hall.id})
    assert hall.id in TrustNetwork.memberships(user.author_id)
    render_click(view, "leave", %{"id" => hall.id})
    assert TrustNetwork.memberships(user.author_id) == []
    {:ok, view, _} = live(conn, "/trust/requests")

    assert render_submit(view, "request", %{
             "kind" => "missing_person",
             "body" => "Please add a researcher"
           }) =~ "Request submitted"

    request = hd(TrustNetwork.requests(user))
    assert {:error, :forbidden} = TrustNetwork.resolve(user, request.id, "resolved", "no")
    {:ok, _} = TrustNetwork.resolve(admin, request.id, "resolved", "Profile reviewed")
    {:ok, updates, html} = live(conn, "/trust/updates")
    assert html =~ "Your evidence request is resolved"
    notice = hd(TrustNetwork.notifications(user))
    render_click(updates, "read", %{"id" => notice.id})
    assert TrustNetwork.unread_count(user) == 0
  end
end
