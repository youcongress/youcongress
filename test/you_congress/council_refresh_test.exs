defmodule YouCongress.CouncilRefreshTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  use Oban.Testing, repo: YouCongress.Repo
  alias YouCongress.{Councils, PeopleLists, Votes}
  alias YouCongress.Councils.{Decision, PeopleListMember}
  alias YouCongress.Workers.RefreshCouncilWorker

  test "async saves invalidate old projections, preserve direct votes and refresh shared-list users" do
    user = user_fixture()
    follower = user_fixture()
    unrelated = user_fixture()
    person = author_fixture()
    replacement = author_fixture()
    statement = statement_fixture()
    direct_statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: replacement.id, statement_id: statement.id, answer: :against})
    {:ok, council} = Councils.add_member(user, person.id)
    source_id = List.last(council.lists).people_list_id

    {:ok, _} =
      PeopleLists.update(user, source_id, %{
        public: true,
        version: List.last(council.lists).list_version
      })

    {:ok, other} = Councils.ensure(follower.author_id)

    {:ok, _} =
      PeopleLists.use_for_council(
        follower,
        source_id,
        List.last(other.lists).id,
        other.version,
        false
      )

    {:ok, untouched} =
      PeopleLists.create(unrelated, %{name: "Unchanged source", public: true, members: []})

    council = Councils.get(user.author_id)

    {:ok, council} =
      PeopleLists.use_for_council(
        user,
        untouched.id,
        hd(council.lists).id,
        council.version,
        false
      )

    vote_fixture(%{
      author_id: user.author_id,
      statement_id: direct_statement.id,
      answer: :abstain,
      direct: true
    })

    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :for
    assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer == :for

    Oban.Testing.with_testing_mode(:manual, fn ->
      attrs = Councils.editable(council)

      lists =
        Enum.map(attrs.lists, fn list ->
          if list.fallback, do: %{list | members: [%{author_id: replacement.id}]}, else: list
        end)

      assert {:ok, _} = Councils.save(user, %{attrs | lists: lists}, refresh: :async)
      assert Councils.delegate_ids(user.author_id) == [replacement.id]
      assert Councils.delegate_ids(follower.author_id) == [replacement.id]
      assert is_nil(Votes.get_by(author_id: user.author_id, statement_id: statement.id))
      assert is_nil(Votes.get_by(author_id: follower.author_id, statement_id: statement.id))

      assert Repo.get_by(Decision, author_id: user.author_id, statement_id: statement.id).council_version ==
               -1

      assert Votes.get_by(author_id: user.author_id, statement_id: direct_statement.id).answer ==
               :abstain

      jobs = all_enqueued(worker: RefreshCouncilWorker)

      assert Enum.sort(Enum.map(jobs, & &1.args["author_id"])) ==
               Enum.sort([user.author_id, follower.author_id])

      for job <- jobs, do: assert(:ok == perform_job(RefreshCouncilWorker, job.args))

      assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer ==
               :against

      assert Votes.get_by(author_id: follower.author_id, statement_id: statement.id).answer ==
               :against

      assert Votes.get_by(author_id: user.author_id, statement_id: direct_statement.id).direct

      # A rejected write neither changes memberships nor schedules more work.
      assert {:error, :stale} = Councils.save(user, attrs, refresh: :async)
      assert Councils.delegate_ids(user.author_id) == [replacement.id]
      assert length(all_enqueued(worker: RefreshCouncilWorker)) == length(jobs)
    end)
  end

  test "adding one person uses a bounded number of queries even with a large Council" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      small = user_fixture()
      large = user_fixture()
      {:ok, _} = Councils.ensure(small.author_id)
      {:ok, large_council} = Councils.ensure(large.author_id)
      existing = for _ <- 1..150, do: author_fixture()
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Repo.insert_all(
        PeopleListMember,
        Enum.with_index(existing, fn person, index ->
          %{
            people_list_id: List.last(large_council.lists).people_list_id,
            author_id: person.id,
            position: index,
            reason: "Keep this reason",
            inserted_at: now,
            updated_at: now
          }
        end)
      )

      target = author_fixture()
      small_queries = measure_add(small, Councils.get(small.author_id), target)
      large_queries = measure_add(large, Councils.get(large.author_id), target)
      assert small_queries > 0
      assert large_queries <= small_queries + 3
      assert length(List.last(Councils.get(large.author_id).lists).members) == 151

      assert hd(List.last(Councils.get(large.author_id).lists).members).reason ==
               "Keep this reason"
    end)
  end

  test "unchanged Council answers retain their date through synchronous and queued refreshes" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, council} = Councils.add_member(user, person.id)
    vote = backdate_council_vote(user, statement)

    assert :ok == YouCongress.DelegationVotes.update_author_delegated_votes(user.author_id)
    assert Repo.get!(YouCongress.Votes.Vote, vote.id).updated_at == vote.updated_at

    Oban.Testing.with_testing_mode(:manual, fn ->
      attrs = Councils.editable(council)
      assert {:ok, _} = Councils.save(user, attrs, refresh: :async)
      assert Repo.get!(YouCongress.Votes.Vote, vote.id).updated_at == vote.updated_at
      assert_pending_vote_hidden(user, statement)

      assert :ok == perform_job(RefreshCouncilWorker, %{author_id: user.author_id})
      refreshed = Votes.get_by(author_id: user.author_id, statement_id: statement.id)
      assert refreshed.id == vote.id
      assert refreshed.inserted_at == vote.inserted_at
      assert refreshed.updated_at == vote.updated_at
      assert refreshed.answer == :for
      assert [%{updated_at: date}] = YouCongress.Councils.Discovery.votes(user.author_id)
      assert date == vote.updated_at
    end)
  end

  test "source changes update the date only when the delegated answer changes" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    source = vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, _} = Councils.add_member(user, person.id)
    vote = backdate_council_vote(user, statement)

    Oban.Testing.with_testing_mode(:manual, fn ->
      # A source edit can invalidate the decision without changing its answer.
      assert :ok ==
               YouCongress.DelegationVotes.enqueue_deleguees_for_delegate_statement(
                 person.id,
                 statement.id
               )

      assert_pending_vote_hidden(user, statement)
      assert :ok == YouCongress.DelegationVotes.update_author_delegated_votes(user.author_id)
      assert Repo.get!(YouCongress.Votes.Vote, vote.id).updated_at == vote.updated_at

      assert {:ok, _} = Votes.update_vote(source, %{answer: :against})
      assert_pending_vote_hidden(user, statement)
      assert Repo.get!(YouCongress.Votes.Vote, vote.id).updated_at == vote.updated_at

      assert :ok ==
               perform_job(YouCongress.Workers.RefreshAuthorStatementDelegatedVotesWorker, %{
                 author_id: user.author_id,
                 statement_id: statement.id
               })

      refreshed = Votes.get_by(author_id: user.author_id, statement_id: statement.id)
      assert refreshed.id == vote.id
      assert refreshed.inserted_at == vote.inserted_at
      assert refreshed.answer == :against
      assert NaiveDateTime.compare(refreshed.updated_at, vote.updated_at) == :gt

      assert :ok == YouCongress.DelegationVotes.update_author_delegated_votes(user.author_id)
      assert Repo.get!(YouCongress.Votes.Vote, vote.id).updated_at == refreshed.updated_at
    end)
  end

  test "losing a deciding Council answer removes the vote and a later answer starts a new date" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, council} = Councils.add_member(user, person.id)
    vote = backdate_council_vote(user, statement)
    attrs = Councils.editable(council)
    lists = Enum.map(attrs.lists, &%{&1 | members: []})

    assert {:ok, _} = Councils.save(user, %{attrs | lists: lists})
    refute Repo.get(YouCongress.Votes.Vote, vote.id)
    assert {:ok, _} = Councils.add_member(user, person.id)
    replacement = Votes.get_by(author_id: user.author_id, statement_id: statement.id)
    assert replacement.id != vote.id
    assert replacement.answer == :for
    assert NaiveDateTime.compare(replacement.updated_at, vote.updated_at) == :gt
  end

  test "a direct override remains visible and keeps its date through Council refresh" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, council} = Councils.add_member(user, person.id)
    delegated = Votes.get_by(author_id: user.author_id, statement_id: statement.id)
    assert {:ok, _} = Votes.update_vote(delegated, %{direct: true, answer: :against})
    direct = backdate_council_vote(user, statement)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = Councils.save(user, Councils.editable(council), refresh: :async)
      assert Votes.get_current_user_vote(statement.id, user.author_id).id == direct.id
      assert :ok == perform_job(RefreshCouncilWorker, %{author_id: user.author_id})
      assert Repo.get!(YouCongress.Votes.Vote, direct.id) == direct
    end)
  end

  test "statement refresh loads the Council once and locks its author first" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, _} = Councils.add_member(user, person.id)
    key = {__MODULE__, make_ref()}
    Process.put(key, [])

    :telemetry.attach(
      key,
      [:you_congress, :repo, :query],
      &__MODULE__.record_query/4,
      {self(), key}
    )

    queries =
      try do
        assert :ok ==
                 YouCongress.DelegationVotes.update_author_statement_delegated_votes(
                   user.author_id,
                   statement.id
                 )

        Enum.reverse(Process.get(key))
      after
        :telemetry.detach(key)
        Process.delete(key)
      end

    assert Enum.count(queries, &String.contains?(&1, ~s(FROM "councils"))) == 1
    assert Enum.count(queries, &String.contains?(&1, ~s(FROM "council_lists"))) == 1
    locks = Enum.filter(queries, &String.contains?(&1, "FOR UPDATE"))
    assert [author_lock, council_lock] = locks
    assert author_lock =~ ~s(FROM "authors")
    assert council_lock =~ ~s(FROM "councils")
    assert Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer == :for
  end

  def record_query(_, _, %{query: query}, {pid, key}) do
    if self() == pid, do: Process.put(key, [query | Process.get(key, [])])
  end

  defp backdate_council_vote(user, statement) do
    vote = Votes.get_by(author_id: user.author_id, statement_id: statement.id)
    old_date = ~N[2020-01-01 12:00:00]

    Repo.update_all(from(v in YouCongress.Votes.Vote, where: v.id == ^vote.id),
      set: [updated_at: old_date]
    )

    Repo.get!(YouCongress.Votes.Vote, vote.id)
  end

  defp assert_pending_vote_hidden(user, statement) do
    refute Votes.get_by(author_id: user.author_id, statement_id: statement.id)
    refute Votes.get_current_user_vote(statement.id, user.author_id)
    assert YouCongress.Councils.Discovery.votes(user.author_id) == []
    assert YouCongress.Councils.Discovery.vote_counts(user.author_id).council == 0
    assert Votes.count_by_author_id(user.author_id) == 0
    assert Votes.count_by_statement(statement.id) == 1
    assert length(Votes.list_votes(statement.id)) == 1
    assert length(Votes.country_result_vote_rows(statement.id)) == 1
    counts = Votes.count_by_response_map_for_statements([statement.id])
    assert Enum.sum(Map.values(counts[statement.id])) == 1
  end

  defp measure_add(user, council, target) do
    attrs = Councils.editable(council)

    lists =
      Enum.map(attrs.lists, fn list ->
        if list.fallback,
          do: %{list | members: list.members ++ [%{author_id: target.id}]},
          else: list
      end)

    key = {__MODULE__, make_ref()}
    Process.put(key, 0)

    :telemetry.attach(
      key,
      [:you_congress, :repo, :query],
      &__MODULE__.count_query/4,
      {self(), key}
    )

    try do
      assert {:ok, _} = Councils.save(user, %{attrs | lists: lists}, refresh: :async)
      Process.get(key)
    after
      :telemetry.detach(key)
      Process.delete(key)
    end
  end

  def count_query(_, _, _, {pid, key}) do
    if self() == pid, do: Process.put(key, Process.get(key, 0) + 1)
  end
end
