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

    view |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()

    render_submit(view, "save", %{
      "public" => "true",
      "name" => "People worth reading",
      "reasons" => %{to_string(person.id) => "Tests ideas carefully"}
    })

    [list] = PeopleLists.for_author(user.author_id)
    assert_redirect(view, YouCongressWeb.PeopleListPaths.public_path(list))
    assert Councils.get(user.author_id) == council
    {:ok, edit, _} = live(conn, "/lists/#{list.id}/edit")

    edit
    |> element("#public-list-editor")
    |> render_change(%{public: "true", name: "Careful researchers"})

    {:ok, show, html} = live(conn, YouCongressWeb.PeopleListPaths.public_path(list))
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
        public: true,
        name: "My reading list",
        members: [%{author_id: person.id, reason: "Worth reading"}]
      })

    {:ok, public, before} = live(conn, YouCongressWeb.PeopleListPaths.public_path(list))
    {:ok, _} = Councils.add_member(owner, person.id)

    {:ok, _} =
      PeopleLists.update(owner, list.id, %{
        name: list.name,
        version: list.version,
        members: [%{author_id: person.id, reason: "Worth reading"}],
        link_council: true
      })

    list = PeopleLists.get(list.id)
    {:ok, _, after_html} = live(conn, YouCongressWeb.PeopleListPaths.public_path(list))

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

    assert path == YouCongressWeb.PeopleListPaths.public_path(list)

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
        public: true,
        name: "Starting points",
        members: [%{author_id: person.id, reason: "Someone else’s words"}]
      })

    {:ok, _} = Councils.add_member(chooser, old.id)
    {:ok, view, html} = live(log_in_user(conn, chooser), "/council?step=pick&use_list=#{list.id}")
    assert html =~ "Use Starting points?"
    assert Councils.delegate_ids(chooser.author_id) == [old.id]
    view |> form("#use-public-list", %{copy: "true"}) |> render_submit()
    assert Councils.delegate_ids(chooser.author_id) == [person.id]

    assert hd(List.last(Councils.get(chooser.author_id).lists).members).reason ==
             "Someone else’s words"

    {:ok, _} =
      PeopleLists.update(owner, list.id, %{
        name: "Changed later",
        version: list.version,
        members: []
      })

    assert Councils.delegate_ids(chooser.author_id) == [person.id]

    assert {:error, {:redirect, %{to: "/sign_up?return_to=%2Fcouncil"}}} =
             live(conn, "/council?step=pick&use_list=#{list.id}")
  end

  test "editable slug preview, canonical username URL, and old links survive a rename", %{
    conn: conn
  } do
    user = user_fixture()

    {:ok, owner} =
      YouCongress.Authors.update_author(YouCongress.Authors.get_author!(user.author_id), %{
        username: "listwriter"
      })

    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/lists/new")

    view
    |> form("#public-list-editor")
    |> render_change(%{public: "true", name: "People I Trust"})

    assert has_element?(view, "#public-list-slug[value=people-i-trust]")
    assert has_element?(view, "#public-list-url-preview", "/@listwriter/lists/people-i-trust")

    view
    |> form("#public-list-editor")
    |> render_change(%{"slug" => "my-picks", "_target" => ["slug"]})

    view
    |> form("#public-list-editor")
    |> render_change(%{public: "true", name: "Different title"})

    assert has_element?(view, "#public-list-slug[value=my-picks]")
    view |> form("#public-list-editor") |> render_submit(%{public: "true"})
    [list] = PeopleLists.for_author(owner.id)
    assert_redirect(view, "/@listwriter/lists/my-picks")
    legacy = get(build_conn(), "/lists/#{list.id}")
    assert legacy.status == 301
    assert redirected_to(legacy, 301) == "/@listwriter/lists/my-picks"
    {:ok, edit, _} = live(conn, "/lists/#{list.id}/edit")
    edit |> form("#public-list-editor") |> render_submit(%{slug: "new-picks"})
    assert has_element?(edit, "#list-autosave-status", "All changes saved")
    assert PeopleLists.get(list.id).slug == "new-picks"

    assert {:error, {:live_redirect, %{to: "/@listwriter/lists/new-picks"}}} =
             live(build_conn(), "/@listwriter/lists/my-picks")

    {:ok, public, _} = live(build_conn(), "/@listwriter/lists/new-picks")
    assert has_element?(public, "button[data-council-copy$='/@listwriter/lists/new-picks']")

    assert {:error, {:live_redirect, %{to: "/@listwriter/lists/new-picks"}}} =
             live(build_conn(), "/a/#{owner.id}/lists/my-picks")
  end

  test "duplicate slug errors preserve form content and authors without usernames can publish", %{
    conn: conn
  } do
    user = user_fixture()

    {:ok, existing} =
      PeopleLists.create(user, %{public: true, name: "Reserved", slug: "reserved", members: []})

    {:ok, view, _} = live(log_in_user(conn, user), "/lists/new")

    view
    |> form("#public-list-editor")
    |> render_submit(%{public: "true", name: "My new list", slug: "reserved"})

    assert has_element?(view, "[role=alert]", "List URL")
    assert has_element?(view, "#public-list-name[value='My new list']")
    assert has_element?(view, "#public-list-url-preview", "/a/#{user.author_id}/lists/reserved")
    assert PeopleLists.for_author(user.author_id) == [existing]
    view |> form("#public-list-editor") |> render_submit(%{slug: "available"})
    assert_redirect(view, "/a/#{user.author_id}/lists/available")
    {:ok, public, _} = live(build_conn(), "/a/#{user.author_id}/lists/available")
    assert has_element?(public, "h1", "My new list")

    {:ok, _} =
      YouCongress.Authors.update_author(YouCongress.Authors.get_author!(user.author_id), %{
        username: "newusername"
      })

    assert {:error, {:live_redirect, %{to: "/@newusername/lists/available"}}} =
             live(build_conn(), "/a/#{user.author_id}/lists/available")
  end

  test "missing authors and slugs do not show another person's list", %{conn: conn} do
    for path <- ["/@missinguser/lists/missing", "/a/invalid/lists/missing", "/a/0/lists/missing"] do
      assert {:error, {:live_redirect, %{to: "/lists"}}} = live(conn, path)
    end

    assert get(conn, "/lists/0").status == 404
  end

  test "existing list additions, removals, and reasons autosave without a save button", %{
    conn: conn
  } do
    user = user_fixture()
    first = author_fixture(%{name: "Picker List Alpha"})
    second = author_fixture(%{name: "Picker List Beta"})

    {:ok, list} =
      PeopleLists.create(user, %{public: true, name: "Editable", members: [], link_council: true})

    {:ok, view, _} = live(log_in_user(conn, user), "/lists/#{list.id}/edit")
    refute has_element?(view, "button", "Save public list")
    assert has_element?(view, "h3", "People to consider")
    assert has_element?(view, "aside h3", "Your list")
    view |> form("#list-person-search-form") |> render_change(%{q: "Picker List"})

    for person <- [first, second] do
      view |> element("#list-candidate-#{person.id} button") |> render_click()
      refute has_element?(view, "#list-candidate-#{person.id}")
      assert Enum.any?(PeopleLists.get(list.id).members, &(&1.author_id == person.id))
      assert person.id in Councils.delegate_ids(user.author_id)
    end

    ids =
      render(view)
      |> Floki.parse_fragment!()
      |> Floki.find("aside [id^=council-member-]")
      |> Floki.attribute("id")

    assert ids == ["council-member-#{second.id}", "council-member-#{first.id}"]
    view |> element("#council-member-#{second.id} button", "+ Add a reason") |> render_click()
    refute has_element?(view, "button", "Save reason")

    render_change(view, "change", %{
      "reasons" => %{to_string(second.id) => "Autosaved public reason"}
    })

    assert hd(PeopleLists.get(list.id).members).reason == "Autosaved public reason"
    assert has_element?(view, "#list-reason-#{second.id}")

    assert Enum.find(
             List.last(Councils.get(user.author_id).lists).members,
             &(&1.author_id == second.id)
           ).reason ==
             "Autosaved public reason"

    render_submit(view, "save", %{
      "action" => "close-reason",
      "reasons" => %{to_string(second.id) => "Final edit before Done"}
    })

    assert has_element?(view, "#council-member-#{second.id} blockquote", "Final edit before Done")
    view |> element("#council-member-#{first.id} button", "Remove") |> render_click()
    assert Enum.map(PeopleLists.get(list.id).members, & &1.author_id) == [second.id]
    assert Councils.delegate_ids(user.author_id) == [second.id]
    assert has_element?(view, "#list-autosave-status", "All changes saved")
  end

  test "autosave validation and conflict errors preserve edits without overwriting saved data", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, list} = PeopleLists.create(user, %{public: true, name: "Original", members: []})
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/lists/#{list.id}/edit")
    view |> form("#public-list-editor") |> render_change(%{public: "true", name: ""})
    assert has_element?(view, "#list-autosave-status", "Not saved")
    assert PeopleLists.get(list.id).name == "Original"
    view |> form("#public-list-editor") |> render_change(%{public: "true", name: "Corrected"})
    assert PeopleLists.get(list.id).name == "Corrected"
    assert has_element?(view, "#list-autosave-status", "All changes saved")
    current = PeopleLists.get(list.id)

    {:ok, _} =
      PeopleLists.update(user, list.id, %{
        version: current.version,
        name: "Another window",
        members: []
      })

    view
    |> form("#public-list-editor")
    |> render_change(%{public: "true", name: "Keep this unsaved text"})

    assert has_element?(view, "#list-autosave-status", "changed in another window")
    assert has_element?(view, "#public-list-name[value='Keep this unsaved text']")
    assert PeopleLists.get(list.id).name == "Another window"
  end

  test "list visibility autosaves and private lists are hidden from other users", %{conn: conn} do
    owner = user_fixture()
    other = user_fixture()
    person = author_fixture()

    {:ok, source} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Shared picks",
        members: [%{author_id: person.id, reason: "A reason"}],
        link_council: true
      })

    {:ok, view, _} = live(log_in_user(conn, owner), "/lists/#{source.id}/edit")
    view |> form("#public-list-editor", %{public: "false"}) |> render_change()
    refute PeopleLists.get(source.id, owner).public
    assert PeopleLists.get(source.id, other) == nil
    assert PeopleLists.for_author(owner.author_id) == []
    refute YouCongress.Councils.Discovery.has_public_reasons?(person.id)

    assert {:error, {:live_redirect, %{to: "/lists"}}} =
             live(
               log_in_user(build_conn(), other),
               YouCongressWeb.PeopleListPaths.public_path(source)
             )

    {:ok, profile, _} = live(build_conn(), "/a/#{owner.author_id}/lists")
    refute render(profile) =~ "Shared picks"
    view |> form("#public-list-editor", %{public: "true"}) |> render_change()
    assert PeopleLists.get(source.id).public
    assert YouCongress.Councils.Discovery.has_public_reasons?(person.id)
  end

  test "a new list defaults to private", %{conn: conn} do
    user = user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/lists/new")
    assert has_element?(view, "#list-visibility option[value=false][selected]")
    view |> form("#public-list-editor", %{name: "My private picks"}) |> render_submit()
    lists = PeopleLists.for_author(user.author_id, user)
    source = Enum.find(lists, &(&1.name == "My private picks"))
    refute source.public
    assert PeopleLists.get(source.id) == nil
  end

  test "saving a reason before naming a new list keeps its slug automatic", %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/lists/new")
    render_click(view, "add-person", %{"id" => person.id})
    render_click(view, "edit-reason", %{"id" => person.id})

    render_change(view, "change", %{
      "name" => "",
      "slug" => "",
      "_target" => ["reasons", to_string(person.id)],
      "reasons" => %{to_string(person.id) => "Early note"}
    })

    render_submit(view, "save", %{
      "action" => "save-reason",
      "name" => "",
      "slug" => "",
      "reasons" => %{to_string(person.id) => "Early note"}
    })

    render_change(view, "change", %{"name" => "Mobile picks", "slug" => "", "_target" => ["name"]})

    assert has_element?(view, "#public-list-slug[value=mobile-picks]")
    view |> form("#public-list-editor") |> render_submit(%{public: "true"})
    [list] = PeopleLists.for_author(user.author_id)
    assert hd(list.members).reason == "Early note"
    assert list.slug == "mobile-picks"
  end
end
