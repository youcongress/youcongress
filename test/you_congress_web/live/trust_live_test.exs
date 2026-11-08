defmodule YouCongressWeb.TrustLiveTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Councils, TrustRankings, PeopleLists}

  test "guest landing, selection, reasons, and signup preserve one draft", %{conn: conn} do
    person = author_fixture(%{name: "A careful researcher"})
    {:ok, view, html} = live(conn, "/council")
    assert html =~ "You don’t have to decide alone."
    refute html =~ "Communities"
    view |> element("a", "Pick my Council →") |> render_click()
    view |> element("form[phx-change=search]") |> render_change(%{q: "careful"})
    view |> element("button[phx-click=add-person]") |> render_click()
    assert render(view) =~ "1 selected"
    view |> element("aside a", "Continue with 1 person") |> render_click()

    view
    |> element("#council-reasons")
    |> render_change(%{reasons: %{to_string(person.id) => "Good judgment"}})

    view |> element("#council-reasons") |> render_submit()
    assert render(view) =~ "Keep your Council."
    assert has_element?(view, "a[href*='pending_actions']")

    signup =
      view
      |> element("a", "Sign up with email/password")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.find("a")
      |> Floki.attribute("href")
      |> hd()

    {:ok, _, html} = live(conn, signup)

    auth_href =
      html
      |> Floki.parse_document!()
      |> Floki.find("a[href^='/auth/google']")
      |> Floki.attribute("href")
      |> hd()

    payload =
      auth_href
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()
      |> Map.fetch!("pending_actions")
      |> Jason.decode!()

    assert hd(hd(payload["council"]["lists"])["members"])["reason"] == "Good judgment"
  end

  test "owner saves reasons, publishes, invites, and returns to My Council", %{conn: conn} do
    user = user_fixture()
    people = for _ <- 1..6, do: author_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, html} = live(conn, "/council?step=pick")
    assert html =~ "Whose judgment do you trust?"
    for person <- people, do: render_click(view, "add-person", %{"id" => person.id})

    render_change(view, "reasons", %{
      "reasons" => %{to_string(hd(people).id) => "Thoughtful judgment"}
    })

    render_click(view, "save")
    assert render(view) =~ "Share a named list?"
    council = Councils.get(user.author_id)
    assert length(hd(council.lists).members) == 6
    refute council.published
    view |> element("#publish-council-list") |> render_submit(%{name: "Careful thinkers"})
    assert render(view) =~ "Who would you invite?"
    refute Councils.public(user.author_id)
    [list] = PeopleLists.for_author(user.author_id)
    {:ok, public, html} = live(build_conn(), "/lists/#{list.id}")
    assert html =~ "Thoughtful judgment"
    refute has_element?(public, "#save-council")
    before = Councils.get(user.author_id)
    render_click(public, "remove-person", %{"id" => hd(people).id})
    render_click(public, "save")
    assert Councils.get(user.author_id) == before
    {:ok, _, html} = live(conn, "/council")
    assert html =~ "My Council"
    assert html =~ "Edit Council"
  end

  test "private Councils count anonymously and only public lists share reasons", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture(%{name: "Trusted Person"})
    {:ok, council} = Councils.add_member(user, person.id)
    attrs = Councils.editable(council)
    [list] = attrs.lists

    {:ok, _} =
      Councils.save(user, %{
        attrs
        | lists: [%{list | members: [%{author_id: person.id, reason: "Private reason"}]}]
      })

    assert redirected_to(get(conn, "/a/#{user.author_id}/council")) ==
             "/a/#{user.author_id}/lists"

    {:ok, _, html} = live(conn, "/trust")
    assert html =~ "Trusted Person"
    refute html =~ "Private reason"
    {:ok, _, html} = live(conn, "/trust/people/#{person.id}")
    refute html =~ "Private reason"

    {:ok, list} =
      PeopleLists.create(user, %{
        name: "Public picks",
        members: [%{author_id: person.id, reason: "Shared reason"}]
      })

    {:ok, _, html} = live(conn, "/trust/people/#{person.id}")
    assert html =~ "Shared reason"
    refute html =~ "Private reason"
    {:ok, _} = PeopleLists.delete(user, list.id)
    {:ok, _, html} = live(conn, "/trust/people/#{person.id}")
    refute html =~ "Shared reason"
    refute html =~ "Private reason"
  end

  test "Trust 30 is one global list with working historical exports", %{conn: conn} do
    user = user_fixture()
    person = author_fixture(%{name: "Trusted Person"})
    {:ok, _} = Councils.add_member(user, person.id)
    {:ok, _, html} = live(conn, "/trust/general?community=123")
    assert html =~ "YouCongress Trust 30"
    assert html =~ "Trusted Person"
    refute html =~ "Community<select"
    response = conn |> get("/trust/general/export.csv") |> response(200)
    assert response =~ "Trusted Person"
    {:ok, snapshot} = TrustRankings.snapshot(admin_fixture(), "general", %{}, "Test snapshot")
    {:ok, _, html} = live(conn, "/trust/snapshots/#{snapshot.id}")
    assert html =~ "Historical snapshot"
    assert redirected_to(get(conn, "/communities")) == "/trust"
    assert redirected_to(get(conn, "/trust/compare")) == "/trust"
  end

  test "reasons open inline for one member, save independently, and cancel without changes", %{
    conn: conn
  } do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    {:ok, _} = Councils.add_member(user, first.id)
    {:ok, _} = Councils.add_member(user, second.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    view |> element("#council-member-#{first.id} button", "+ Add a reason") |> render_click()
    assert has_element?(view, "#council-member-#{first.id} textarea")
    refute has_element?(view, "#council-member-#{second.id} textarea")
    refute has_element?(view, "#council-reasons")

    view
    |> form("#council-reason-#{first.id}", reason: "Careful with evidence")
    |> render_submit()

    assert has_element?(view, "#council-member-#{first.id} blockquote", "Careful with evidence")
    refute has_element?(view, "textarea")
    saved = hd(Councils.get(user.author_id).lists).members
    assert Enum.find(saved, &(&1.author_id == first.id)).reason == "Careful with evidence"
    assert Enum.find(saved, &(&1.author_id == second.id)).reason == nil

    view |> element("#council-member-#{first.id} button", "Edit reason") |> render_click()
    assert has_element?(view, "textarea", "Careful with evidence")
    view |> form("#council-reason-#{first.id}", reason: "Unsaved edit") |> render_change()
    view |> element("button", "Cancel") |> render_click()
    refute has_element?(view, "textarea")
    assert has_element?(view, "#council-member-#{first.id} blockquote", "Careful with evidence")
    assert hd(Councils.get(user.author_id).lists).members == saved
  end

  test "inline reason conflicts keep the typed text and do not overwrite newer Council changes",
       %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    added_elsewhere = author_fixture()
    {:ok, _} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    view |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()
    {:ok, newer} = Councils.add_member(user, added_elsewhere.id)
    view |> form("#council-reason-#{person.id}", reason: "Keep my draft") |> render_submit()
    assert has_element?(view, "[role=alert]", "Your Council changed in another window")
    assert has_element?(view, "textarea", "Keep my draft")
    assert Councils.get(user.author_id) == newer
  end
end
