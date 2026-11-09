defmodule YouCongress.CouncilRefreshConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias YouCongress.{Councils, DelegationVotes, Repo, Votes}
  alias YouCongress.Accounts.User
  alias YouCongress.Authors.Author
  alias YouCongress.Councils.{Council, Decision, List, PeopleList}
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
