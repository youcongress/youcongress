defmodule YouCongress.Statements.SynthesisTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.Synthesis
  alias YouCongress.Workers.StatementSynthesisWorker

  defp enable_synthesis_flag do
    original = Application.fetch_env(:you_congress, :feature_flags)

    flags =
      case original do
        {:ok, map} when is_map(map) -> Map.put(map, :quote_synthesis, true)
        _ -> %{quote_synthesis: true}
      end

    Application.put_env(:you_congress, :feature_flags, flags)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:you_congress, :feature_flags, value)
        :error -> Application.delete_env(:you_congress, :feature_flags)
      end
    end)
  end

  describe "eligible?/2" do
    test "false when the feature flag is disabled" do
      refute Synthesis.eligible?(%Statement{synthesis: nil}, 30)
    end

    test "requires the quote floor when there is no synthesis yet" do
      enable_synthesis_flag()
      refute Synthesis.eligible?(%Statement{synthesis: nil}, 24)
      assert Synthesis.eligible?(%Statement{synthesis: nil}, 25)
    end

    test "requires the staleness delta when a synthesis exists" do
      enable_synthesis_flag()
      statement = %Statement{synthesis: %{"headline" => "x"}, synthesis_quotes_count: 25}

      refute Synthesis.eligible?(statement, 34)
      assert Synthesis.eligible?(statement, 35)
    end

    test "treats a missing synthesis_quotes_count as zero" do
      enable_synthesis_flag()
      statement = %Statement{synthesis: %{"headline" => "x"}, synthesis_quotes_count: nil}

      assert Synthesis.eligible?(statement, 25)
    end
  end

  describe "sanitize/2" do
    test "keeps valid clusters, drops foreign/duplicate/non-integer ids and blank items" do
      raw = %{
        "headline" => "Headline.",
        "arguments_for" => [
          %{"title" => "A", "summary" => "S", "opinion_ids" => [1, 1, 99, 2, "x"]}
        ],
        "arguments_against" => [
          %{"title" => "B", "summary" => "S", "opinion_ids" => [99]},
          %{"title" => "", "summary" => "S", "opinion_ids" => [1]},
          %{"title" => "C", "summary" => "S", "opinion_ids" => [3]}
        ],
        "middle_ground" => [],
        "insights" => ["i1", "", 42, "i2"],
        "conclusion" => "Conclusion.",
        "model" => "gpt-test"
      }

      assert {:ok, clean} = Synthesis.sanitize(raw, MapSet.new([1, 2, 3]))

      assert [%{"title" => "A", "opinion_ids" => [1, 2]}] = clean["arguments_for"]
      assert [%{"title" => "C", "opinion_ids" => [3]}] = clean["arguments_against"]
      assert clean["middle_ground"] == []
      assert clean["insights"] == ["i1", "i2"]
      assert clean["headline"] == "Headline."
      assert clean["conclusion"] == "Conclusion."
      assert clean["model"] == "gpt-test"
    end

    test "caps clusters, opinion ids and insights" do
      cluster = fn n ->
        %{"title" => "t#{n}", "summary" => "s", "opinion_ids" => Enum.to_list(1..8)}
      end

      raw = %{
        "headline" => "H",
        "conclusion" => "C",
        "arguments_for" => Enum.map(1..6, cluster),
        "arguments_against" => [],
        "middle_ground" => [],
        "insights" => Enum.map(1..7, &"insight #{&1}")
      }

      assert {:ok, clean} = Synthesis.sanitize(raw, MapSet.new(1..10))

      assert length(clean["arguments_for"]) == 5
      assert Enum.all?(clean["arguments_for"], &(length(&1["opinion_ids"]) == 6))
      assert length(clean["insights"]) == 5
    end

    test "rejects the decode-failure shape and payloads missing headline or conclusion" do
      valid_ids = MapSet.new([1])

      assert {:error, :invalid_synthesis} = Synthesis.sanitize(%{"model" => "x"}, valid_ids)

      assert {:error, :invalid_synthesis} =
               Synthesis.sanitize(%{"headline" => "H"}, valid_ids)

      assert {:error, :invalid_synthesis} =
               Synthesis.sanitize(%{"headline" => " ", "conclusion" => "C"}, valid_ids)

      assert {:error, :invalid_synthesis} = Synthesis.sanitize("not a map", valid_ids)
    end
  end

  describe "cited_opinion_ids/1" do
    test "collects unique ids across all cluster sections" do
      synthesis = %{
        "arguments_for" => [%{"opinion_ids" => [1, 2]}, %{"opinion_ids" => [2, 3]}],
        "arguments_against" => [%{"opinion_ids" => [3, 4]}],
        "middle_ground" => [%{"no_ids" => true}]
      }

      assert Synthesis.cited_opinion_ids(synthesis) == [1, 2, 3, 4]
      assert Synthesis.cited_opinion_ids(nil) == []
    end
  end

  describe "maybe_enqueue/1" do
    test "enqueues a synthesis job when eligible" do
      enable_synthesis_flag()
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Synthesis.maybe_enqueue(Statements.get_statement!(statement.id))

        assert [_job] = all_enqueued(worker: StatementSynthesisWorker)
      end)
    end

    test "does nothing when the feature flag is off" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok = Synthesis.maybe_enqueue(Statements.get_statement!(statement.id))

        assert [] = all_enqueued(worker: StatementSynthesisWorker)
      end)
    end

    test "generates and persists a synthesis through the fake pipeline" do
      # Oban runs inline in tests: enqueue -> submit -> poll -> persist.
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)
      enable_synthesis_flag()

      assert :ok = Synthesis.maybe_enqueue(Statements.get_statement!(statement.id))

      statement = Statements.get_statement!(statement.id)
      assert statement.synthesis["headline"] =~ "Fake synthesis"
      assert statement.synthesis_quotes_count == 25
      assert %DateTime{} = statement.synthesis_generated_at

      cited = Synthesis.cited_opinion_ids(statement.synthesis)
      assert cited != []
      assert MapSet.subset?(MapSet.new(cited), Synthesis.valid_quote_ids(statement.id))
    end
  end

  describe "backfill/1" do
    test "returns candidates without enqueuing on dry_run and enqueues otherwise" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)
      small = statement_fixture(%{title: "too few quotes"})
      fill_statement_with_quotes(small.id, 3)
      statement_id = statement.id

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert [{%Statement{id: ^statement_id}, 25}] = Synthesis.backfill(dry_run: true)
        assert [] = all_enqueued(worker: StatementSynthesisWorker)

        assert [{%Statement{id: ^statement_id}, 25}] = Synthesis.backfill([])
        assert [job] = all_enqueued(worker: StatementSynthesisWorker)
        assert job.args == %{"statement_id" => statement_id, "force" => true}
      end)
    end

    test "skips statements with a synthesis unless forced" do
      statement = statement_fixture()
      fill_statement_with_quotes(statement.id, 25)

      {:ok, statement} =
        Statements.update_synthesis(statement, %{
          synthesis: %{"headline" => "H", "conclusion" => "C"},
          synthesis_quotes_count: 25
        })

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert [] = Synthesis.backfill(dry_run: true)
        assert [{_statement, 25}] = Synthesis.backfill(dry_run: true, force: true)
      end)

      _ = statement
    end
  end
end
