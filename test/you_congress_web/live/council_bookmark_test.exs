defmodule YouCongressWeb.CouncilBookmarkTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.Councils

  test "profile quick save uses the final General, then edits repeated lists in place", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    attrs = Councils.editable(council)
    extra = %{name: "Inner circle", hall_id: nil, members: []}
    governance = hd(attrs.lists)
    repeat = %{name: "Other governance", hall_id: governance.hall_id, members: []}
    {:ok, council} = Councils.save(user, %{attrs | lists: [extra, repeat | attrs.lists]})
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"

    assert view |> element(root <> " > button") |> render_click() =~
             "Added to the General council."

    saved = Councils.get(user.author_id)
    assert Enum.map(List.last(saved.lists).members, & &1.author_id) == [person.id]
    assert Enum.all?(Enum.drop(saved.lists, -1), &(&1.members == []))
    assert has_element?(view, root <> " > button", "In my council")

    view |> element(root <> " button", "Choose lists") |> render_click()

    assert length(
             view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find(root <> " input[type=checkbox]")
           ) == 5

    selected = [hd(council.lists).id, Enum.at(council.lists, 1).id, governance.id]

    view
    |> element(root <> " form")
    |> render_change(%{"lists" => ["" | Enum.map(selected, &to_string/1)]})

    saved = Councils.get(user.author_id)
    assert List.last(saved.lists).members == []
    assert Enum.map(Enum.filter(saved.lists, &(&1.members != [])), & &1.id) == selected
    assert has_element?(view, root <> " [role=dialog]")
    view |> element(root) |> render_hook("dismiss", %{notice: "1"})
    assert has_element?(view, root <> " [role=dialog]")

    view |> element(root <> " form") |> render_change(%{"lists" => [""]})
    assert Enum.all?(Councils.get(user.author_id).lists, &(&1.members == []))
    assert has_element?(view, root <> " > button", "Add to council")
  end

  test "vote cards add immediately and a compact confirmation can expire", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    statement = YouCongress.StatementsFixtures.statement_fixture()

    YouCongress.VotesFixtures.vote_fixture(
      %{author_id: person.id, statement_id: statement.id},
      true
    )

    {:ok, view, _} = live(log_in_user(conn, user), "/p/#{statement.slug}")
    view |> element("[id^=vote-council-] > button") |> render_click()
    assert person.id in Councils.delegate_ids(user.author_id)

    assert has_element?(
             view,
             "[id^=vote-council-] [role=status]",
             "Added to the General council."
           )

    view |> element("div[id^=vote-council-][phx-hook]") |> render_hook("dismiss", %{notice: "1"})
    refute has_element?(view, "[id^=vote-council-] [role=dialog]")
    assert person.id in Councils.delegate_ids(user.author_id)
  end

  test "stale checkbox selections and another user's list cannot replace council edits", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    {:ok, changed} = Councils.save(user, Councils.editable(council))

    assert view |> element(root <> " form") |> render_change(%{"lists" => [""]}) =~
             "changed elsewhere"

    assert person.id in Councils.delegate_ids(user.author_id)
    {:ok, other} = Councils.ensure(user_fixture().author_id)

    assert {:error, :invalid_list} =
             Councils.set_member_lists(user, person.id, [hd(other.lists).id], changed.version)

    assert person.id in Councils.delegate_ids(user.author_id)
  end

  test "guest quick save requests authentication and retains the chosen person", %{conn: conn} do
    person = author_fixture()
    {:ok, view, _} = live(conn, "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    assert view |> element(root <> " > button") |> render_click() =~ "Sign in to add"
    assert has_element?(view, root <> " a[href*=pending_actions]")
    refute has_element?(view, root <> " [role=status]", "Added")
  end

  test "council reasons still save without a source field", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, _} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    refute has_element?(view, "input[name=source_url]")

    render_change(view, "reason", %{
      "person_id" => to_string(person.id),
      "list" => "2",
      "reason" => "Thoughtful judgment"
    })

    render_click(view, "save")

    assert hd(List.last(Councils.get(user.author_id).lists).members).reason ==
             "Thoughtful judgment"
  end
end
