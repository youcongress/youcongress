defmodule YouCongress.CouncilDefaultsMigrationTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.{Councils, Halls, HallsStatements, PeopleLists, Votes}
  alias YouCongress.Councils.{Decision, PeopleList, PeopleListMember}
  alias YouCongress.Workers.RefreshCouncilWorker
  alias YouCongress.Repo.Migrations.NormalizeCouncilDefaults

  test "normalizes old defaults without deleting lists, reasons or direct votes" do
    user = user_fixture()
    current_user = user_fixture()
    yes = author_fixture()
    no = author_fixture()
    statement = statement_fixture()
    direct_statement = statement_fixture()
    vote_fixture(%{author_id: yes.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: no.id, statement_id: statement.id, answer: :against})
    direct = vote_fixture(%{author_id: user.author_id, statement_id: direct_statement.id})
    {:ok, environment} = Halls.get_or_create_by_name("environment")
    {:ok, jobs} = Halls.get_or_create_by_name("impact-on-jobs")
    {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "environment", other_tags: []})
    {:ok, council} = Councils.ensure(user.author_id)
    {:ok, current} = Councils.ensure(current_user.author_id)
    [gov, labor, fallback] = Councils.editable(council).lists

    {:ok, council} =
      Councils.save(user, %{
        version: council.version,
        lists: [
          gov,
          %{labor | hall_id: jobs.id, name: "Impact on jobs"},
          %{
            hall_id: environment.id,
            name: "Environment",
            members: [%{author_id: no.id, reason: "Keep this explanation"}]
          },
          %{fallback | name: "General", members: [%{author_id: yes.id}]}
        ]
      })

    environment_list = Enum.at(council.lists, 2).people_list_id
    sources = Repo.all(PeopleList)
    members = Repo.all(PeopleListMember)
    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :against

    Oban.Testing.with_testing_mode(:manual, fn ->
      run_migration()
      updated = Councils.get(user.author_id)

      assert Enum.map(updated.lists, & &1.name) == [
               "AI governance",
               "Impact on labor",
               "All statements"
             ]

      assert Enum.map(updated.lists, & &1.position) == [0, 1, 2]

      assert Enum.map(updated.lists, & &1.hall_id) == [
               gov.hall_id,
               Halls.get_by_name("impact-on-labor").id,
               nil
             ]

      assert updated.version == council.version + 1
      assert Councils.get(current_user.author_id).version == current.version
      assert Repo.get!(PeopleList, environment_list).name == "Environment"
      assert Repo.get!(YouCongress.Halls.Hall, environment.id)
      assert Repo.all(PeopleListMember) == members

      assert Map.new(Repo.all(PeopleList), &{&1.id, &1.slug}) ==
               Map.new(sources, &{&1.id, &1.slug})

      assert Repo.get_by(Decision, author_id: user.author_id, statement_id: statement.id).council_version ==
               -1

      refute Votes.get_by(author_id: user.author_id, statement_id: statement.id)
      assert Votes.get_vote!(direct.id) == direct
      assert [%{args: %{"author_id" => author_id}}] = all_enqueued(worker: RefreshCouncilWorker)
      assert author_id == user.author_id

      # Re-running the data cleanup is harmless and does not enqueue duplicate work.
      run_migration()
      assert Councils.get(user.author_id).version == updated.version
      assert length(all_enqueued(worker: RefreshCouncilWorker)) == 1
      assert :ok == perform_job(RefreshCouncilWorker, %{author_id: user.author_id})
      assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :for
      assert Votes.get_vote!(direct.id) == direct
    end)
  end

  test "keeps public and custom list names while removing repeated Environment assignments" do
    user = user_fixture()
    owner = user_fixture()
    person = author_fixture()
    {:ok, environment} = Halls.get_or_create_by_name("environment")
    {:ok, jobs} = Halls.get_or_create_by_name("impact-on-jobs")

    {:ok, public} =
      PeopleLists.create(owner, %{
        name: "General",
        public: true,
        members: [%{author_id: person.id, reason: "Public reason"}]
      })

    {:ok, council} = Councils.ensure(user.author_id)
    [gov, labor, fallback] = Councils.editable(council).lists

    {:ok, council} =
      Councils.save(user, %{
        version: council.version,
        lists: [
          gov,
          %{labor | hall_id: jobs.id, name: "My labor experts"},
          %{hall_id: environment.id, name: "Environment", members: []},
          %{hall_id: environment.id, name: "Another environment list", members: []},
          fallback
        ]
      })

    {:ok, council} =
      PeopleLists.use_for_council(
        user,
        public.id,
        List.last(council.lists).id,
        council.version,
        false
      )

    before_members = Repo.all(PeopleListMember)

    run_migration()

    assert Enum.map(Councils.get(user.author_id).lists, & &1.name) == [
             "AI governance",
             "My labor experts",
             "General"
           ]

    assert Repo.get!(PeopleList, public.id) |> Repo.preload(:members) == public
    assert Repo.all(PeopleListMember) == before_members
    assert length(Councils.get(user.author_id).lists) == 3
    assert council.version + 1 == Councils.get(user.author_id).version
  end

  defp run_migration do
    unless Code.ensure_loaded?(NormalizeCouncilDefaults) do
      Code.require_file(
        "../../priv/repo/migrations/20261109120000_normalize_council_defaults.exs",
        __DIR__
      )
    end

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      20_261_109_120_000,
      NormalizeCouncilDefaults,
      :forward,
      :up,
      :up,
      log: false
    )
  end
end
