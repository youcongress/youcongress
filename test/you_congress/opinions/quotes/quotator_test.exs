defmodule YouCongress.Opinions.Quotes.QuotatorTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Opinions.Quotes.Quotator
  alias YouCongress.Workers.QuotatorWorker
  alias YouCongress.Workers.VerificationWorker
  alias YouCongress.{Authors, Votes, Opinions}

  defp candidate(attrs \\ %{}) do
    Map.merge(
      %{
        "quote" =>
          "We should adopt the complete policy because its safeguards and benefits justify doing so.",
        "source_url" => "https://example.com/verified-policy-quote",
        "date" => Date.utc_today() |> Date.to_iso8601(),
        "date_precision" => "day",
        "author" => %{
          "name" => "Verified Policy Expert",
          "bio" => "Policy expert",
          "wikipedia_url" => "https://en.wikipedia.org/wiki/Verified_Policy_Expert",
          "twitter_username" => "verifiedexpert"
        },
        "agree_rate" => "For",
        "validation_note" => "Exact source text and an unambiguous vote."
      },
      attrs
    )
  end

  describe "find_and_save_quotes/6 with QuotatorFake" do
    test "returns the same contract as the AI quotator and creates votes/opinions" do
      statement = statement_fixture(%{title: "Test Statement Title"})
      user = user_fixture(%{name: "Test User"})

      exclude = ["Excluded Name"]

      assert {:ok, :job_started} =
               Quotator.find_and_save_quotes(statement.id, exclude, user.id, 1, 1)

      # The fake persists quotes synchronously, but exposes the same return value as production.
      assert Votes.count_by_statement(statement.id) == Quotator.number_of_quotes()

      votes = Votes.list_votes(statement.id)
      # Votes should be direct and not twins
      assert Enum.all?(votes, &(&1.direct == true and &1.twin == false))

      # Each vote should have a valid answer
      assert Enum.all?(votes, fn v -> v.answer in [:for, :against, :abstain] end)

      # Opinions should be created and linked to the votes
      assert Enum.count(votes, &(not is_nil(&1.opinion_id))) == Quotator.number_of_quotes()

      # Opinions should have stored a date with explicit precision
      Enum.each(votes, fn v ->
        opinion = Opinions.get_opinion!(v.opinion_id)
        assert %Date{} = opinion.date
        assert opinion.date_precision == :year
      end)
    end
  end

  describe "save_quotes_from_job/1" do
    test "persists a valid candidate with its statement link and vote" do
      statement = statement_fixture()
      user = user_fixture()

      assert {:ok, 1} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate()],
                 user_id: user.id
               })

      opinion = Opinions.get_by(content: candidate()["quote"], preload: :statements)
      vote = Votes.get_by(statement_id: statement.id, author_id: opinion.author_id)

      assert Enum.map(opinion.statements, & &1.id) == [statement.id]
      assert opinion.user_id == user.id
      assert vote.opinion_id == opinion.id
      assert vote.answer == :for
    end

    test "fills missing metadata on an existing author matched by name" do
      statement = statement_fixture()
      user = user_fixture()

      author =
        author_fixture(%{
          name: "Verified Policy Expert",
          bio: nil,
          twitter_username: nil,
          wikipedia_url: nil,
          twin_origin: false
        })

      assert {:ok, 1} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate()],
                 user_id: user.id
               })

      opinion = Opinions.get_by(content: candidate()["quote"])
      reloaded_author = Authors.get_author!(author.id)

      assert opinion.author_id == author.id
      assert reloaded_author.bio == "Policy expert"
      assert reloaded_author.twitter_username == "verifiedexpert"

      assert reloaded_author.wikipedia_url ==
               "https://en.wikipedia.org/wiki/Verified_Policy_Expert"
    end

    test "does not overwrite existing author metadata" do
      statement = statement_fixture()
      user = user_fixture()

      author =
        author_fixture(%{
          name: "Verified Policy Expert",
          bio: "Existing bio",
          twitter_username: "existingexpert",
          wikipedia_url: "https://en.wikipedia.org/wiki/Verified_Policy_Expert",
          twin_origin: false
        })

      assert {:ok, 1} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate()],
                 user_id: user.id
               })

      opinion = Opinions.get_by(content: candidate()["quote"])
      reloaded_author = Authors.get_author!(author.id)

      assert opinion.author_id == author.id
      assert reloaded_author.bio == "Existing bio"
      assert reloaded_author.twitter_username == "existingexpert"

      assert reloaded_author.wikipedia_url ==
               "https://en.wikipedia.org/wiki/Verified_Policy_Expert"
    end

    test "rejects an unclear vote instead of silently storing it as abstain" do
      statement = statement_fixture()
      user = user_fixture()

      assert {:ok, 0} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate(%{"agree_rate" => "None"})],
                 user_id: user.id
               })

      assert Votes.count_by_statement(statement.id) == 0
      assert is_nil(Opinions.get_by(content: candidate()["quote"]))
    end

    test "rejects a sourced quote outside the current-year discovery window" do
      statement = statement_fixture()
      user = user_fixture()
      stale_year = Date.utc_today().year - 1

      assert {:ok, 0} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [
                   candidate(%{"date" => to_string(stale_year), "date_precision" => "year"})
                 ],
                 user_id: user.id
               })

      assert Votes.count_by_statement(statement.id) == 0
    end

    test "enqueues the normal quote verification cascade" do
      statement = statement_fixture()
      user = user_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 1} =
                 Quotator.save_quotes_from_job(%{
                   statement_id: statement.id,
                   quotes: [candidate()],
                   user_id: user.id
                 })

        opinion = Opinions.get_by(content: candidate()["quote"])

        assert_enqueued(
          worker: VerificationWorker,
          args: %{"subject" => "quote", "id" => opinion.id}
        )
      end)
    end

    test "does not overwrite an existing vote for a returned author" do
      statement = statement_fixture()

      author =
        author_fixture(%{
          name: "Verified Policy Expert",
          wikipedia_url: "https://en.wikipedia.org/wiki/Verified_Policy_Expert"
        })

      existing_vote =
        vote_fixture(%{statement_id: statement.id, author_id: author.id, answer: :against})

      assert {:ok, 0} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate()],
                 user_id: user_fixture().id
               })

      unchanged_vote = Votes.get_by(statement_id: statement.id, author_id: author.id)
      assert unchanged_vote.id == existing_vote.id
      assert unchanged_vote.answer == :against
      assert is_nil(Opinions.get_by(content: candidate()["quote"]))
    end

    test "skips duplicate source URLs and normalized quote content" do
      statement = statement_fixture()
      user = user_fixture()

      duplicate_content =
        candidate(%{
          "quote" =>
            "  WE SHOULD ADOPT THE COMPLETE POLICY BECAUSE ITS SAFEGUARDS AND BENEFITS JUSTIFY DOING SO. ",
          "source_url" => "https://example.com/a-second-source",
          "author" => Map.put(candidate()["author"], "name", "A Second Expert")
        })

      assert {:ok, 1} =
               Quotator.save_quotes_from_job(%{
                 statement_id: statement.id,
                 quotes: [candidate(), duplicate_content],
                 user_id: user.id
               })

      assert Votes.count_by_statement(statement.id) == 1
    end
  end

  describe "quote discovery lifecycle" do
    test "reports the initial finder job as in progress and deduplicates requests" do
      statement = statement_fixture()
      user = user_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        refute Quotator.find_quotes_in_progress?(statement.id)

        assert {:ok, first_job} = Quotator.enqueue_find_quotes(statement.id, user.id)
        assert Quotator.find_quotes_in_progress?(statement.id)

        assert {:ok, duplicate_job} = Quotator.enqueue_find_quotes(statement.id, user.id)
        assert duplicate_job.id == first_job.id
        assert duplicate_job.conflict?

        assert_enqueued(worker: QuotatorWorker, args: %{"statement_id" => statement.id})
      end)
    end
  end
end
