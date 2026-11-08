defmodule YouCongressWeb.TrustLiveTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Councils, TrustRankings, PeopleLists}

  test "guest landing starts signup and returns to Council after confirmation", %{conn: conn} do
    {:ok, view, html} = live(conn, "/council")
    assert html =~ "If you could choose the people overseeing AI,"
    assert html =~ "who would you choose—and why?"
    assert html =~ "Coming soon"
    assert html =~ "Your private Council choices contribute anonymously."
    assert html =~ "Your Council is private. Sharing a list is optional."
    signup = "/sign_up?return_to=%2Fcouncil"
    assert has_element?(view, "a[href='#{signup}']", "Start choosing →")
    assert has_element?(view, "a[href='#{signup}']", "Pick my Council →")
    refute has_element?(view, "#person-search")
    {:ok, registration, _} = live(conn, signup)
    assert has_element?(registration, "a[href='/auth/google?return_to=%2Fcouncil']")
    user = user_fixture(%{}, nil, false)
    {:ok, confirmed} = YouCongress.Accounts.confirm_user_email(user)
    signed_in = log_in_user(conn, confirmed)
    assert {:error, {:redirect, %{to: "/council"}}} = live(signed_in, signup)
    {:ok, council, _} = live(signed_in, "/council")
    assert has_element?(council, "#council-onboarding", "Start with people you trust.")
  end

  test "old guest picking links and draft events require signup", %{conn: conn} do
    for path <- [
          "/council?step=pick",
          "/council?step=join",
          "/council?step=why",
          "/council?use_list=1",
          "/council?add=1"
        ] do
      assert {:error, {:redirect, %{to: "/sign_up?return_to=%2Fcouncil"}}} = live(conn, path)
    end

    {:ok, view, _} = live(conn, "/council")
    render_hook(view, "restore-draft", %{draft: %{lists: []}})
    assert_redirect(view, "/sign_up?return_to=%2Fcouncil")
  end

  test "Council invitations survive signup without a guest draft", %{conn: conn} do
    inviter = user_fixture()
    ref = to_string(inviter.author_id)
    {:ok, view, _} = live(conn, "/council?ref=#{ref}")

    signup =
      view
      |> element("a", "Pick my Council →")
      |> render()
      |> Floki.parse_fragment!()
      |> Floki.attribute("href")
      |> hd()

    params = signup |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert params["return_to"] == "/council"
    assert Jason.decode!(params["pending_actions"]) == %{"council_ref" => ref}
    {:ok, registration, _} = live(conn, signup)
    assert has_element?(registration, "a[href^='/auth/google?pending_actions=']")
  end

  test "owner saves reasons, publishes, invites, and returns to My Council", %{conn: conn} do
    user = user_fixture()
    people = for _ <- 1..6, do: author_fixture()
    conn = log_in_user(conn, user)
    for person <- people, do: Councils.add_member(user, person.id)
    topic = List.last(Councils.get(user.author_id).lists)
    {:ok, editor, _} = live(conn, "/lists/#{topic.people_list_id}/edit")

    render_change(editor, "change", %{
      "reasons" => %{to_string(hd(people).id) => "Thoughtful judgment"}
    })

    {:ok, view, _} = live(conn, "/council?step=publish&list=#{topic.id}")

    assert render(view) =~ "Share a named list?"
    council = Councils.get(user.author_id)
    assert length(List.last(council.lists).members) == 6
    refute council.published
    view |> form("#publish-council-list") |> render_change(%{name: "Careful thinkers"})
    assert has_element?(view, "#public-list-slug[value=careful-thinkers]")
    view |> form("#publish-council-list") |> render_submit(%{slug: "trusted-voices"})
    assert render(view) =~ "Who would you invite?"
    refute Councils.public(user.author_id)
    [list] = PeopleLists.for_author(user.author_id)
    assert list.slug == "trusted-voices"
    assert PeopleLists.linked_list(user).id == list.id
    {:ok, public, html} = live(build_conn(), YouCongressWeb.PeopleListPaths.public_path(list))
    assert html =~ "Thoughtful judgment"
    refute has_element?(public, "#save-council")
    before = Councils.get(user.author_id)
    render_click(public, "remove-person", %{"id" => hd(people).id})
    render_click(public, "save")
    assert Councils.get(user.author_id) == before
    :ok = Councils.complete_onboarding(user)
    {:ok, _, html} = live(conn, "/council")
    assert html =~ "My Council"
    assert html =~ "AI governance"
    {:ok, _, html} = live(conn, "/council?step=pick")
    assert html =~ "Careful thinkers"
  end

  test "private Councils count anonymously and only public lists share reasons", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture(%{name: "Trusted Person"})
    {:ok, council} = Councils.add_member(user, person.id)
    attrs = Councils.editable(council)
    list = List.last(attrs.lists)

    {:ok, _} =
      Councils.save(user, %{
        attrs
        | lists: [%{list | members: [%{author_id: person.id, reason: "Private reason"}]}]
      })

    assert redirected_to(get(conn, "/a/#{user.author_id}/council")) ==
             "/a/#{user.author_id}/lists"

    conn = log_in_user(conn, admin_fixture())
    {:ok, _, html} = live(conn, "/trust")
    assert html =~ "Trusted Person"
    refute html =~ "Private reason"
    {:ok, _, html} = live(conn, "/a/#{person.id}/trust")
    refute html =~ "Private reason"

    {:ok, list} =
      PeopleLists.create(user, %{
        public: true,
        name: "Public picks",
        members: [%{author_id: person.id, reason: "Shared reason"}]
      })

    {:ok, _, html} = live(conn, "/a/#{person.id}/trust")
    assert html =~ "Shared reason"
    refute html =~ "Private reason"
    {:ok, _} = PeopleLists.delete(user, list.id)
    {:ok, _, html} = live(conn, "/a/#{person.id}/trust")
    refute html =~ "Shared reason"
    refute html =~ "Private reason"
  end

  test "Trust 30 is one global list with working historical exports", %{conn: conn} do
    user = user_fixture()
    person = author_fixture(%{name: "Trusted Person"})
    {:ok, _} = Councils.add_member(user, person.id)
    conn = log_in_user(conn, admin_fixture())
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

  test "reasons open inline for one member and autosave independently", %{
    conn: conn
  } do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    {:ok, _} = Councils.add_member(user, first.id)
    {:ok, _} = Councils.add_member(user, second.id)
    source_id = List.last(Councils.get(user.author_id).lists).people_list_id
    {:ok, view, _} = live(log_in_user(conn, user), "/lists/#{source_id}/edit")
    view |> element("#council-member-#{first.id} button", "+ Add a reason") |> render_click()
    assert has_element?(view, "#council-member-#{first.id} textarea")
    refute has_element?(view, "#council-member-#{second.id} textarea")
    refute has_element?(view, "#council-reasons")

    render_submit(view, "save", %{
      "action" => "close-reason",
      "reasons" => %{to_string(first.id) => "Careful with evidence"}
    })

    assert has_element?(view, "#council-member-#{first.id} blockquote", "Careful with evidence")
    refute has_element?(view, "textarea")
    saved = List.last(Councils.get(user.author_id).lists).members
    assert Enum.find(saved, &(&1.author_id == first.id)).reason == "Careful with evidence"
    assert Enum.find(saved, &(&1.author_id == second.id)).reason == nil

    view |> element("#council-member-#{first.id} button", "Edit reason") |> render_click()
    assert has_element?(view, "textarea", "Careful with evidence")
    render_change(view, "change", %{"reasons" => %{to_string(first.id) => "Autosaved edit"}})
    updated = List.last(Councils.get(user.author_id).lists).members
    assert Enum.find(updated, &(&1.author_id == first.id)).reason == "Autosaved edit"
    assert Enum.find(updated, &(&1.author_id == second.id)).reason == nil
  end

  test "inline reason conflicts keep the typed text and do not overwrite newer Council changes",
       %{conn: conn} do
    user = user_fixture()
    person = author_fixture()
    added_elsewhere = author_fixture()
    {:ok, _} = Councils.add_member(user, person.id)
    source_id = List.last(Councils.get(user.author_id).lists).people_list_id
    {:ok, view, _} = live(log_in_user(conn, user), "/lists/#{source_id}/edit")
    view |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()
    {:ok, newer} = Councils.add_member(user, added_elsewhere.id)
    render_change(view, "change", %{"reasons" => %{to_string(person.id) => "Keep my draft"}})
    assert has_element?(view, "#list-autosave-status", "changed")
    assert has_element?(view, "textarea", "Keep my draft")
    assert Councils.get(user.author_id) == newer
  end

  test "the old why link opens the compact entry editor", %{conn: conn} do
    user = user_fixture()
    {:ok, view, html} = live(log_in_user(conn, user), "/council?step=why")
    assert html =~ "Edit Council entry"
    refute html =~ "Say why"
    refute has_element?(view, "#person-search")
    assert has_element?(view, "a", "Edit list")
  end

  test "Trust rankings and exports require an admin, and public pages hide ranking entry points",
       %{conn: conn} do
    person = author_fixture()
    admin = admin_fixture()
    {:ok, snapshot} = TrustRankings.snapshot(admin, "general", %{}, "Admin preview")
    {:ok, moderator} = YouCongress.Accounts.update_role(user_fixture(), "moderator")

    for viewer <- [nil, user_fixture(), moderator] do
      viewer_conn = if viewer, do: log_in_user(build_conn(), viewer), else: conn

      for path <- [
            "/trust",
            "/trust/general",
            "/trust/general/export.csv",
            "/trust/snapshots/#{snapshot.id}",
            "/trust/snapshots/#{snapshot.id}/export.csv",
            "/trust/metrics"
          ] do
        assert redirected_to(get(viewer_conn, path)) == "/log_in"
      end

      for path <- ["/council", "/council?step=pick", "/a/#{person.id}"] do
        if is_nil(viewer) && path == "/council?step=pick" do
          assert {:error, {:redirect, %{to: "/sign_up?return_to=%2Fcouncil"}}} =
                   live(viewer_conn, path)
        else
          {:ok, view, html} = live(viewer_conn, path)
          refute has_element?(view, "a[href='/trust']")
          refute has_element?(view, "a[href^='/trust/people/']")

          if is_nil(viewer) && path == "/council",
            do: assert(html =~ "Coming soon"),
            else: refute(html =~ "Trust 30")
        end
      end
    end

    {:ok, view, _} = live(log_in_user(conn, admin), "/council?step=mine")
    assert has_element?(view, "a[href='/trust']")
  end

  test "an open Trust List rejects navigation after admin access is revoked", %{conn: conn} do
    admin = admin_fixture()
    {:ok, view, _} = live(log_in_user(conn, admin), "/trust")
    {:ok, _} = YouCongress.Accounts.update_role(admin, "user")
    render_patch(view, "/trust?tab=statements")
    assert_redirect(view, "/")
  end
end
