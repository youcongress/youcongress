defmodule YouCongressWeb.AuthorTrustTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Authors, Councils, PeopleLists}

  test "profile links reflect public content, never private Council reasons", %{conn: conn} do
    owner = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.add_member(owner, person.id)
    attrs = Councils.editable(council)
    list = List.last(attrs.lists)

    {:ok, _} =
      Councils.save(owner, %{
        attrs
        | lists: [%{list | members: [%{author_id: person.id, reason: "Private judgment"}]}]
      })

    {:ok, profile, _} = live(conn, "/a/#{person.id}")
    refute has_element?(profile, "a", "Why people trust them")
    {:ok, profile, _} = live(conn, "/a/#{owner.author_id}")
    refute has_element?(profile, "a", "Public lists")

    {:ok, list} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Thoughtful people",
        members: [%{author_id: person.id, reason: "   "}]
      })

    {:ok, profile, _} = live(conn, "/a/#{owner.author_id}")
    assert has_element?(profile, "a[href='/a/#{owner.author_id}/lists']", "Public lists")
    {:ok, profile, _} = live(conn, "/a/#{person.id}")
    refute has_element?(profile, "a", "Why people trust them")

    {:ok, list} =
      PeopleLists.update(owner, list.id, %{
        name: list.name,
        slug: list.slug,
        version: list.version,
        members: [%{author_id: person.id, reason: "Explains the evidence"}]
      })

    {:ok, profile, _} = live(conn, "/a/#{person.id}")
    assert has_element?(profile, "a[href='/a/#{person.id}/trust']", "Why people trust them")
    refute has_element?(profile, "a", "Public lists")
    {:ok, reasons, html} = live(conn, "/a/#{person.id}/trust")
    assert html =~ "Explains the evidence"
    refute html =~ "Private judgment"
    refute html =~ "Trust 30"
    assert has_element?(reasons, "a[href='/a/#{person.id}']", "Where they stand")
    refute has_element?(reasons, "a[href*='tab=statements']")

    {:ok, _} = PeopleLists.delete(owner, list.id)
    {:ok, profile, _} = live(conn, "/a/#{person.id}")
    refute has_element?(profile, "a", "Why people trust them")
    {:ok, profile, _} = live(conn, "/a/#{owner.author_id}")
    refute has_element?(profile, "a", "Public lists")
  end

  test "username profile links and legacy redirects use the same public destinations", %{
    conn: conn
  } do
    owner = user_fixture()

    {:ok, author} =
      Authors.update_author(Authors.get_author!(owner.author_id), %{username: "publicwriter"})

    person = author_fixture(%{username: "carefulthinker"})

    {:ok, list} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Careful thinkers",
        members: [%{author_id: person.id, reason: "Checks assumptions"}]
      })

    {:ok, profile, _} = live(conn, "/@publicwriter")
    assert has_element?(profile, "a[href='/@publicwriter/lists']", "Public lists")
    {:ok, lists, _} = live(conn, "/@publicwriter/lists")
    assert has_element?(lists, "a[href='/@publicwriter/lists/#{list.slug}']")
    {:ok, _, html} = live(conn, "/a/#{author.id}/lists")
    assert html =~ "Careful thinkers"

    {:ok, profile, _} = live(conn, "/@carefulthinker")
    assert has_element?(profile, "a[href='/@carefulthinker/trust']", "Why people trust them")
    {:ok, reasons, html} = live(conn, "/@carefulthinker/trust")
    assert html =~ "Checks assumptions"
    assert has_element?(reasons, "a[href='/@carefulthinker']", "Where they stand")

    assert {:error, {:live_redirect, %{to: "/@carefulthinker/trust"}}} =
             live(conn, "/a/#{person.id}/trust")

    assert redirected_to(get(conn, "/trust/people/#{person.id}"), 301) == "/@carefulthinker/trust"

    assert redirected_to(get(conn, "/trust/people/#{person.id}?tab=statements"), 301) ==
             "/@carefulthinker"

    assert {:error, {:live_redirect, %{to: "/@carefulthinker"}}} =
             live(conn, "/@carefulthinker/trust?tab=statements")
  end

  test "old numeric person URLs redirect for visitors and unknown people return 404", %{
    conn: conn
  } do
    person = author_fixture()
    assert redirected_to(get(conn, "/trust/people/#{person.id}"), 301) == "/a/#{person.id}/trust"

    assert redirected_to(get(conn, "/trust/people/#{person.id}?tab=statements"), 301) ==
             "/a/#{person.id}"

    assert response(get(conn, "/trust/people/invalid"), 404)
    assert response(get(conn, "/trust/people/0"), 404)
  end

  test "blocked publishers do not expose reasons or reason links", %{conn: conn} do
    owner = user_fixture()
    person = author_fixture()

    {:ok, _} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Picks",
        members: [%{author_id: person.id, reason: "Hidden reason"}]
      })

    {:ok, _} = YouCongress.Accounts.update_role(owner, "blocked")
    {:ok, profile, _} = live(conn, "/a/#{person.id}")
    refute has_element?(profile, "a", "Why people trust them")
    {:ok, _, html} = live(conn, "/a/#{person.id}/trust")
    refute html =~ "Hidden reason"
    assert html =~ "No public reasons yet"
  end

  test "ranking links lead to profiles and show reasons only when published", %{conn: conn} do
    owner = user_fixture()
    person = author_fixture(%{username: "rankedthinker"})
    {:ok, _} = Councils.add_member(owner, person.id)
    conn = log_in_user(conn, admin_fixture())
    {:ok, ranking, _} = live(conn, "/trust")
    assert has_element?(ranking, "a[href='/@rankedthinker']", person.name)
    refute has_element?(ranking, "a[href='/@rankedthinker/trust']")

    {:ok, _} =
      PeopleLists.create(owner, %{
        public: true,
        name: "Picks",
        members: [%{author_id: person.id, reason: "Public evidence"}]
      })

    {:ok, ranking, _} = live(conn, "/trust")
    assert has_element?(ranking, "a[href='/@rankedthinker/trust']", "Read reasons")
  end
end
