defmodule YouCongressWeb.CouncilLoadingTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  alias YouCongress.{Councils, PeopleLists}

  test "navigation loads invitations, candidates and votes only on the relevant page", %{
    conn: conn
  } do
    user = admin_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    entry = List.last(council.lists)
    {:ok, view, _} = live(log_in_user(conn, user), "/council?step=mine")

    for step <- ["mine", "pick", "publish", "votes", "invite"] do
      queries = patch_queries(view, "/council?step=#{step}&list=#{entry.id}")

      invitation_reads =
        Enum.filter(queries, &String.contains?(&1, ~s(FROM "council_invitations")))

      assert length(invitation_reads) == if(step == "invite", do: 1, else: 0)
      refute Enum.any?(queries, &String.contains?(&1, "ILIKE"))
      refute Enum.any?(queries, &String.contains?(&1, ~s(JOIN "people_list_members")))
      refute Enum.any?(queries, &String.contains?(&1, ~s(JOIN "opinions")))
      assert Enum.count(queries, &String.contains?(&1, ~s(FROM "people_lists"))) == 1

      vote_reads = Enum.filter(queries, &String.contains?(&1, ~s(FROM "votes")))
      assert length(vote_reads) == if(step == "votes", do: 1, else: 0)
    end

    queries = patch_queries(view, "/council?step=people&list=#{entry.id}")
    assert has_element?(view, "#person-search-form")
    assert Enum.any?(queries, &String.contains?(&1, ~s(JOIN "people_list_members")))
    refute Enum.any?(queries, &String.contains?(&1, ~s(FROM "council_invitations")))

    queries = patch_queries(view, "/council?step=onboarding")
    assert has_element?(view, "#council-onboarding")
    assert Enum.any?(queries, &String.contains?(&1, ~s(JOIN "opinions")))
    refute Enum.any?(queries, &String.contains?(&1, ~s(JOIN "people_list_members")))
  end

  test "list deep links load the entry editor after overriding another requested step", %{
    conn: conn
  } do
    user = user_fixture()
    owner = YouCongress.Repo.preload(user_fixture(), :author)
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    entry = hd(council.lists)

    {:ok, list} =
      PeopleLists.create(owner, %{
        name: "Shared experts",
        public: true,
        members: [%{author_id: person.id}]
      })

    {:ok, view, _} =
      live(
        log_in_user(conn, user),
        "/council?step=invite&use_list=#{list.id}&list=#{entry.id}"
      )

    assert has_element?(view, "#council-entry")
    assert has_element?(view, "#use-public-list", "Use Shared experts?")
    refute has_element?(view, "#council-invites")
    view |> form("#use-public-list") |> render_submit()
    assert has_element?(view, ".yc-entry-preview", person.name)
    assert has_element?(view, "#council-linked-list", owner.author.name)
    assert hd(Councils.get(user.author_id).lists).people_list_id == list.id

    {:ok, _} = PeopleLists.update(owner, list.id, %{public: false, version: list.version})
    render_patch(view, "/council?step=pick&list=#{entry.id}")
    assert has_element?(view, "#council-linked-list", "List unavailable")
    refute has_element?(view, ".yc-entry-preview")
    refute render(view) =~ "Shared experts"
  end

  test "add-person links refresh the selected entry preview after overriding the votes step", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    entry = hd(council.lists)

    {:ok, view, _} =
      live(
        log_in_user(conn, user),
        "/council?step=votes&add=#{person.id}&list=#{entry.id}"
      )

    assert has_element?(view, "#council-entry")
    assert has_element?(view, ".yc-entry-preview", person.name)
    assert [%{author_id: id}] = hd(Councils.get(user.author_id).lists).members
    assert id == person.id
    assert List.last(Councils.get(user.author_id).lists).members == []
  end

  defp patch_queries(view, path) do
    key = {__MODULE__, make_ref()}

    :telemetry.attach(
      key,
      [:you_congress, :repo, :query],
      &__MODULE__.record_query/4,
      {self(), view.pid, key}
    )

    try do
      render_patch(view, path)
      collect_queries(key)
    after
      :telemetry.detach(key)
    end
  end

  defp collect_queries(key) do
    receive do
      {^key, query} -> [query | collect_queries(key)]
    after
      0 -> []
    end
  end

  def record_query(_, _, %{query: query}, {recipient, view_pid, key}) do
    if self() == view_pid, do: send(recipient, {key, query})
  end
end
