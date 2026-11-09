defmodule YouCongressWeb.CouncilOnboardingTest do
  use YouCongressWeb.ConnCase
  import Phoenix.LiveViewTest
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  use Oban.Testing, repo: YouCongress.Repo
  alias YouCongress.{Councils, PeopleLists}

  test "onboarding suggests people by opinion count and still allows searching anyone", %{
    conn: conn
  } do
    user = user_fixture()
    prolific = author_fixture(%{name: "Zelda Most Opinions"})
    fewer = author_fixture(%{name: "Alice Fewer Opinions"})
    no_opinions = author_fixture(%{name: "No Opinions Yet"})
    twin_only = author_fixture(%{name: "Generated Opinions Only"})

    for {author_id, count, twin} <- [
          {prolific.id, 3, false},
          {fewer.id, 1, false},
          {user.author_id, 5, false},
          {twin_only.id, 6, true}
        ],
        _ <- 1..count do
      YouCongress.Repo.insert!(%YouCongress.Opinions.Opinion{
        author_id: author_id,
        content: "An opinion",
        twin: twin
      })
    end

    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    candidates = view |> element("#council-candidates") |> render() |> Floki.parse_fragment!()

    assert Floki.attribute(Floki.find(candidates, "[id^=council-candidate-]"), "id") == [
             "council-candidate-#{prolific.id}",
             "council-candidate-#{fewer.id}"
           ]

    view |> form("#person-search-form", %{q: no_opinions.name}) |> render_change()
    assert has_element?(view, "#council-candidate-#{no_opinions.id}")
    view |> form("#person-search-form", %{q: ""}) |> render_change()
    refute has_element?(view, "#council-candidate-#{no_opinions.id}")
    view |> element("#council-candidate-#{prolific.id} button") |> render_click()
    assert has_element?(view, "#council-member-#{prolific.id}")
    refute has_element?(view, "#council-candidate-#{prolific.id}")
    assert has_element?(view, "#council-candidate-#{fewer.id}")
  end

  test "first choices and reasons autosave to All statements, then completion persists", %{
    conn: conn
  } do
    user = user_fixture()
    person = author_fixture(%{name: "Onboarding Thoughtful Person"})
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/council")
    assert has_element?(view, "#council-onboarding")
    view |> form("#person-search-form", %{q: person.name}) |> render_change()
    view |> element("#council-candidate-#{person.id} button") |> render_click()
    assert has_element?(view, "#council-member-#{person.id}")
    refute has_element?(view, "#council-candidate-#{person.id}")
    view |> element("#council-member-#{person.id} button", "+ Add a reason") |> render_click()

    view
    |> form("#council-reason-#{person.id}", %{reason: "Carefully weighs the evidence"})
    |> render_change()

    council = Councils.get(user.author_id)
    assert Enum.all?(Enum.drop(council.lists, -1), &(&1.members == []))

    assert [%{author_id: id, reason: "Carefully weighs the evidence"}] =
             List.last(council.lists).members

    assert id == person.id
    refute council.onboarding_completed

    {:ok, resumed, _} = live(conn, "/council")
    assert has_element?(resumed, "#council-onboarding")
    assert has_element?(resumed, "#council-member-#{person.id}", "Carefully weighs the evidence")
    resumed |> element("#finish-council-onboarding") |> render_click()
    assert_patch(resumed, "/council")
    refute has_element?(resumed, "#council-onboarding")
    refute has_element?(resumed, "#person-search")
    refute has_element?(resumed, "#council-candidates")
    refute render(resumed) =~ "People to consider"
    assert has_element?(resumed, "nav[aria-label='My Council']")
    refute has_element?(resumed, "#council-people-picker")
    refute has_element?(resumed, "#council-member-#{person.id}")
    fallback = List.last(council.lists)
    resumed |> element("#topic-list-#{fallback.id} button", "Edit people") |> render_click()
    assert has_element?(resumed, "#council-member-#{person.id}")
    resumed |> element("#council-member-#{person.id} button", "Remove") |> render_click()
    {:ok, returning, _} = live(conn, "/council")
    refute has_element?(returning, "#council-onboarding")
    assert Councils.get(user.author_id).onboarding_completed
    assert List.last(Councils.get(user.author_id).lists).members == []
  end

  test "removing people from a large list saves immediately and queues vote refresh", %{
    conn: conn
  } do
    user = user_fixture()
    people = for _ <- 1..55, do: author_fixture()
    [first, second | remaining] = people
    statement = YouCongress.StatementsFixtures.statement_fixture()

    YouCongress.VotesFixtures.vote_fixture(%{
      author_id: first.id,
      statement_id: statement.id,
      answer: :for
    })

    {:ok, council} = Councils.ensure(user.author_id)
    attrs = Councils.editable(council)

    lists =
      Enum.map(attrs.lists, fn list ->
        if list.fallback,
          do: %{
            list
            | members: Enum.map(people, &%{author_id: &1.id, reason: "Keep this reason"})
          },
          else: list
      end)

    {:ok, council} = Councils.save(user, %{attrs | lists: lists})
    fallback = List.last(council.lists)
    assert YouCongress.Votes.get_by(author_id: user.author_id, statement_id: statement.id)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, view, _} =
        live(log_in_user(conn, user), "/council?list=#{fallback.id}&step=people")

      # LiveView handles clicks in its own process; keep its jobs queued too.
      :sys.replace_state(view.pid, fn state ->
        Process.put(:oban_testing, :manual)
        state
      end)

      for person <- [first, second] do
        view |> element("#council-member-#{person.id} button", "Remove") |> render_click()
        refute has_element?(view, "#council-member-#{person.id}")
      end

      saved = List.last(Councils.get(user.author_id).lists)
      assert Enum.map(saved.members, & &1.author_id) == Enum.map(remaining, & &1.id)
      assert Enum.all?(saved.members, &(&1.reason == "Keep this reason"))
      assert has_element?(view, ".yc-badge", "53 selected")

      # The old projection remains stored until the worker runs, but is hidden from readers.
      assert YouCongress.Repo.get_by(YouCongress.Votes.Vote,
               author_id: user.author_id,
               statement_id: statement.id
             )

      refute YouCongress.Votes.get_by(author_id: user.author_id, statement_id: statement.id)
      assert [%{args: args}] = all_enqueued(worker: YouCongress.Workers.RefreshCouncilWorker)
      assert args == %{"author_id" => user.author_id}
      assert :ok == perform_job(YouCongress.Workers.RefreshCouncilWorker, args)

      refute YouCongress.Repo.get_by(YouCongress.Votes.Vote,
               author_id: user.author_id,
               statement_id: statement.id
             )
    end)
  end

  test "normal Council edits the chosen topic directly without changing the fallback", %{
    conn: conn
  } do
    user = user_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    :ok = Councils.complete_onboarding(user)
    person = author_fixture()
    topic = hd(council.lists)
    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    view |> element("#topic-list-#{topic.id} button", "Choose people") |> render_click()
    assert_patch(view, "/council?list=#{topic.id}&step=people")
    assert has_element?(view, "#council-choose-people")
    render_click(view, "add-person", %{id: person.id})
    council = Councils.get(user.author_id)
    assert [%{author_id: id}] = hd(council.lists).members
    assert id == person.id
    assert List.last(council.lists).members == []
    assert has_element?(view, "#council-member-#{person.id}")
    refute has_element?(view, "#council-entry")
    view |> element("a", "Back to My Council →") |> render_click()
    assert_patch(view, "/council")
    refute has_element?(view, "#person-search")
    refute has_element?(view, "#council-candidates")
    refute has_element?(view, "#council-people-picker")
  end

  test "an existing public list can be used privately during onboarding and copied inline", %{
    conn: conn
  } do
    owner = user_fixture()
    user = user_fixture()
    person = author_fixture()

    {:ok, list} =
      PeopleLists.create(owner, %{
        name: "Thoughtful people",
        public: true,
        members: [%{author_id: person.id}]
      })

    {:ok, view, _} = live(log_in_user(conn, user), "/council")
    view |> element("button", "Use an existing list instead") |> render_click()

    view
    |> form("#search-public-lists", %{scope: "all", q: "Thoughtful people"})
    |> render_change()

    view |> element("#public-list-option-#{list.id} button") |> render_click()
    view |> form("#use-public-list") |> render_submit()
    assert has_element?(view, "#council-onboarding")
    assert List.last(Councils.get(user.author_id).lists).people_list_id == list.id
    refute has_element?(view, "#person-search")
    render_click(view, "add-person", %{id: author_fixture().id})
    assert length(PeopleLists.get(list.id, owner).members) == 1
    view |> element("button", "Make a private copy") |> render_click()
    assert has_element?(view, "#council-onboarding")
    assert has_element?(view, "#person-search")
    source = List.last(Councils.get(user.author_id).lists)
    refute source.public
    assert source.list_owner_id == user.author_id
    refute source.people_list_id == list.id
    assert source.members |> Enum.map(& &1.author_id) == [person.id]
  end

  test "onboarding can be skipped without choices and will not return", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _} = live(conn, "/council")
    view |> element("#finish-council-onboarding") |> render_click()
    {:ok, view, _} = live(conn, "/council")
    refute has_element?(view, "#council-onboarding")
  end
end
