defmodule YouCongress.CouncilRefreshConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias YouCongress.{Councils, DelegationVotes, PeopleLists, Repo, Votes}
  alias YouCongress.Accounts.User
  alias YouCongress.Authors.Author
  alias YouCongress.Councils.{Council, Decision, List, PeopleList, PeopleListMember}
  alias YouCongress.Statements.Statement
  alias YouCongress.Votes.Vote

  test "Council saves and statement refreshes finish on separate database connections" do
    # Separate committed connections are necessary to exercise PostgreSQL row locks.
    Sandbox.unboxed_run(Repo, fn ->
      owner = Repo.insert!(%Author{name: "Concurrent Council owner"})
      person = Repo.insert!(%Author{name: "Concurrent Council member"})

      statement =
        Repo.insert!(%Statement{
          title: "Concurrent Council refresh",
          slug: "concurrent-council-#{System.unique_integer([:positive])}"
        })

      try do
        council = Repo.insert!(%Council{author_id: owner.id})

        source =
          Repo.insert!(%PeopleList{author_id: owner.id, name: "All statements", slug: "all"})

        Repo.insert!(%List{
          council_id: council.id,
          people_list_id: source.id,
          position: 0,
          fallback: true
        })

        Repo.insert!(%Vote{
          author_id: person.id,
          statement_id: statement.id,
          direct: true,
          origin: "self_cast",
          answer: :for
        })

        parent = self()

        tasks = [
          concurrent_task(parent, fn ->
            user = %User{author_id: owner.id}

            for iteration <- 1..5 do
              attrs = Councils.editable(Councils.get(owner.id))

              lists =
                Enum.map(attrs.lists, fn list ->
                  %{list | members: [%{author_id: person.id, reason: "Revision #{iteration}"}]}
                end)

              assert {:ok, _} = Councils.save(user, %{attrs | lists: lists}, refresh: :async)
            end
          end),
          concurrent_task(parent, fn ->
            for _ <- 1..5 do
              assert :ok ==
                       DelegationVotes.update_author_statement_delegated_votes(
                         owner.id,
                         statement.id
                       )
            end
          end)
        ]

        try do
          for task <- tasks do
            pid = task.pid
            assert_receive {:ready, ^pid}, 5_000
          end

          Enum.each(tasks, &send(&1.pid, :go))
          Task.await_many(tasks, 15_000)

          assert :ok ==
                   DelegationVotes.update_author_statement_delegated_votes(owner.id, statement.id)

          assert Votes.get_by(author_id: owner.id, statement_id: statement.id).answer == :for
          decision = Repo.get_by!(Decision, author_id: owner.id, statement_id: statement.id)
          assert decision.council_version == Councils.get(owner.id).version
        after
          Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
        end
      after
        Repo.delete_all(
          from j in Oban.Job,
            where: fragment("?->>'author_id'", j.args) == ^to_string(owner.id)
        )

        Repo.delete!(owner)
        Repo.delete!(person)
        Repo.delete!(statement)
      end
    end)
  end

  test "removing a member allows a follower to reference the locked list and its owner" do
    Sandbox.unboxed_run(Repo, fn ->
      owner = Repo.insert!(%Author{name: "Shared list owner"})
      follower = Repo.insert!(%Author{name: "Shared list follower"})
      person = Repo.insert!(%Author{name: "Member to remove"})

      try do
        source =
          Repo.insert!(%PeopleList{
            author_id: owner.id,
            name: "Shared list",
            slug: "shared",
            public: true
          })

        other =
          Repo.insert!(%PeopleList{author_id: follower.id, name: "Other list", slug: "other"})

        for {id, position} <- Enum.with_index([owner.id, person.id]) do
          Repo.insert!(%PeopleListMember{
            people_list_id: source.id,
            author_id: id,
            position: position
          })
        end

        council = Repo.insert!(%Council{author_id: follower.id})

        Repo.insert!(%List{
          council_id: council.id,
          people_list_id: source.id,
          position: 0
        })

        target =
          Repo.insert!(%List{
            council_id: council.id,
            people_list_id: other.id,
            position: 1,
            fallback: true
          })

        parent = self()

        assignment =
          concurrent_task(parent, fn ->
            try do
              Repo.transaction(fn ->
                Repo.query!("SET LOCAL lock_timeout = '1s'")
                {:ok, locked} = Councils.ensure(follower.id)
                send(parent, :follower_locked)
                await_signal(:assign_source)

                PeopleLists.use_for_council(
                  %User{author_id: follower.id},
                  source.id,
                  target.id,
                  locked.version,
                  false
                )
              end)
            rescue
              error in Postgrex.Error -> {:error, error}
            end
          end)

        removal =
          concurrent_task(parent, fn ->
            handler = {__MODULE__, make_ref()}

            :telemetry.attach(
              handler,
              [:you_congress, :repo, :query],
              &__MODULE__.pause_list_write/4,
              {self(), parent}
            )

            try do
              PeopleLists.update(%User{author_id: owner.id}, source.id, %{
                version: source.version,
                members: [%{author_id: owner.id}]
              })
            after
              :telemetry.detach(handler)
            end
          end)

        try do
          for task <- [assignment, removal] do
            pid = task.pid
            assert_receive {:ready, ^pid}, 5_000
          end

          send(assignment.pid, :go)
          assert_receive :follower_locked, 5_000
          send(removal.pid, :go)
          assert_receive :list_locked, 5_000
          send(assignment.pid, :assign_source)

          # The assignment must finish while the edit holds the list and author
          # locks. Otherwise the edit's Council invalidation creates a deadlock.
          assert {:ok, {:ok, _}} = Task.await(assignment, 5_000)
          send(removal.pid, :continue_removal)
          assert {:ok, updated} = Task.await(removal, 5_000)
          assert Enum.map(updated.members, & &1.author_id) == [owner.id]
          assert Councils.delegate_ids(follower.id) == [owner.id]
          assert Repo.get!(List, target.id).people_list_id == source.id
        after
          Enum.each([assignment, removal], &Task.shutdown(&1, :brutal_kill))
        end
      after
        Repo.delete!(follower)
        Repo.delete!(owner)
        Repo.delete!(person)
      end
    end)
  end

  def pause_list_write(_, _, %{query: query}, {pid, parent}) do
    if self() == pid && String.contains?(query, ~s(FROM "people_lists")) &&
         String.contains?(query, "FOR ") do
      send(parent, :list_locked)
      await_signal(:continue_removal)
    end
  end

  defp await_signal(signal) do
    receive do
      ^signal -> :ok
    after
      5_000 -> flunk("Timed out waiting for #{signal}")
    end
  end

  defp concurrent_task(parent, fun) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        Oban.Testing.with_testing_mode(:manual, fn ->
          Repo.query!("SET statement_timeout = '10s'")
          send(parent, {:ready, self()})

          try do
            receive do
              :go -> fun.()
            after
              5_000 -> flunk("Concurrent operation was not started")
            end
          after
            Repo.query!("RESET statement_timeout")
          end
        end)
      end)
    end)
  end
end
