defmodule YouCongressWeb.PeopleListsTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{PeopleLists, Councils}

  test "owner creates, edits, and deletes a named list without changing their Council", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture(%{name: "Independent thinker"})
    {:ok, council} = Councils.ensure(user.author_id)
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/lists/new")
    render_change(view, "search", %{"q" => "Independent thinker"})
    view |> element("button[phx-click=add-person]") |> render_click()

    view
    |> element("#public-list-editor")
    |> render_submit(%{
      name: "People worth reading",
      reasons: %{to_string(person.id) => "Tests ideas carefully"}
    })

    [list] = PeopleLists.for_author(user.author_id)
    assert_redirect(view, "/lists/#{list.id}")
    assert Councils.get(user.author_id) == council
    {:ok, edit, _} = live(conn, "/lists/#{list.id}/edit")
    edit |> element("#public-list-editor") |> render_submit(%{name: "Careful researchers"})
    {:ok, show, html} = live(conn, "/lists/#{list.id}")
    assert html =~ "Careful researchers"
    assert html =~ "Tests ideas carefully"
    show |> element("button[phx-click=delete]") |> render_click()
    assert PeopleLists.get(list.id) == nil
    assert Councils.get(user.author_id) == council
  end

  test "public pages reveal no Council association and readers cannot mutate lists", %{conn: conn} do
    owner = user_fixture()
    viewer = user_fixture()
    person = author_fixture()

    {:ok, list} =
      PeopleLists.create(owner, %{
        name: "My reading list",
        members: [%{author_id: person.id, reason: "Worth reading"}]
      })

    {:ok, public, before} = live(conn, "/lists/#{list.id}")
    {:ok, _} = Councils.add_member(owner, person.id)
    {:ok, _, after_html} = live(conn, "/lists/#{list.id}")

    public_content = fn html ->
      html |> Floki.parse_document!() |> Floki.find(".yc-content") |> Floki.raw_html()
    end

    assert public_content.(before) == public_content.(after_html)

    for html <- [before, after_html] do
      assert html =~ "Worth reading"
      refute html =~ "Private Council"
      refute html =~ "Manage this list"
      refute html =~ "Used as"
    end

    render_click(public, "delete")
    render_click(public, "save", %{"name" => "Hacked"})
    assert PeopleLists.get(list.id) == list

    assert {:error, {:live_redirect, %{to: path}}} =
             live(log_in_user(conn, viewer), "/lists/#{list.id}/edit")

    assert path == "/lists/#{list.id}"

    assert redirected_to(get(conn, "/a/#{owner.author_id}/council")) ==
             "/a/#{owner.author_id}/lists"
  end

  test "using a list is a private reviewable copy and does not create a live connection", %{
    conn: conn
  } do
    owner = user_fixture()
    chooser = user_fixture()
    old = author_fixture()
    person = author_fixture()

    {:ok, list} =
      PeopleLists.create(owner, %{
        name: "Starting points",
        members: [%{author_id: person.id, reason: "Someone else’s words"}]
      })

    {:ok, _} = Councils.add_member(chooser, old.id)
    {:ok, view, html} = live(log_in_user(conn, chooser), "/council?step=pick&use_list=#{list.id}")
    assert html =~ "Copied people from"
    assert Councils.delegate_ids(chooser.author_id) == [old.id]
    render_click(view, "save")
    assert Councils.delegate_ids(chooser.author_id) == [person.id]
    refute hd(hd(Councils.get(chooser.author_id).lists).members).reason

    {:ok, _} =
      PeopleLists.update(owner, list.id, %{
        name: "Changed later",
        version: list.version,
        members: []
      })

    assert Councils.delegate_ids(chooser.author_id) == [person.id]
    {:ok, guest, _} = live(conn, "/council?step=pick&use_list=#{list.id}")
    render_hook(guest, "restore-draft", %{draft: %{lists: [%{members: [%{author_id: old.id}]}]}})
    assert render(guest) =~ "0 selected"
  end
end
