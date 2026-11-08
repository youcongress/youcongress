defmodule YouCongressWeb.CouncilBookmarkTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.Councils

  test "profile adds to one Council and supports removal", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    assert view |> element(root <> " > button") |> render_click() =~ "Added to your Council."
    assert person.id in Councils.delegate_ids(user.author_id)
    assert length(Councils.get(user.author_id).lists) == 1
    view |> element(root <> " > button") |> render_click()
    assert has_element?(view, root <> " button", "Remove from my Council")
    refute has_element?(view, root <> " input[type=checkbox]")
    view |> element(root <> " button", "Remove from my Council") |> render_click()
    refute person.id in Councils.delegate_ids(user.author_id)
  end

  test "compact confirmations expire without removing selections", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    view |> element(root) |> render_hook("dismiss", %{notice: "1"})
    refute has_element?(view, root <> " [role=dialog]")
    assert person.id in Councils.delegate_ids(user.author_id)
  end

  test "stale removal cannot overwrite edits from another window", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(user, person.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    view |> element(root <> " > button") |> render_click()
    {:ok, _} = Councils.save(user, Councils.editable(council))

    assert view |> element(root <> " button", "Remove from my Council") |> render_click() =~
             "changed elsewhere"

    assert person.id in Councils.delegate_ids(user.author_id)
  end

  test "guest retains the selected person through authentication", %{conn: conn} do
    person = author_fixture()
    {:ok, view, _} = live(conn, "/a/#{person.id}")
    root = "#profile-council-#{person.id}"
    assert view |> element(root <> " > button") |> render_click() =~ "Sign in to add"
    assert has_element?(view, root <> " a[href*=pending_actions]")
  end
end
