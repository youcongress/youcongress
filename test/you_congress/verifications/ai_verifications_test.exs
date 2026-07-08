defmodule YouCongress.Verifications.AIVerificationsTest do
  @moduledoc """
  Exercises the automated verification cascade (quote -> relevance -> vote) using
  network-free stub verifiers. Oban runs `:inline` in tests, so enqueuing a
  verification job runs the whole cascade synchronously.
  """
  use YouCongress.DataCase

  alias YouCongress.Authors
  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
  alias YouCongress.Verifications
  alias YouCongress.Verifications.AIVerifications
  alias YouCongress.VoteVerifications
  alias YouCongress.Votes
  alias YouCongress.Workers.VerificationWorker

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures

  # --- Stub verifiers ---------------------------------------------------------

  defmodule PositiveVerifier do
    @behaviour YouCongress.Verifications.Verifier
    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("vote:" <> _),
      do: {:ok, :completed, %{"correct_answer" => "for", "comment" => "c", "model" => "m"}}

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}
  end

  defmodule DisputedRelevanceVerifier do
    @behaviour YouCongress.Verifications.Verifier
    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("quote:" <> _),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}

    def check_job_status("relevance:" <> _),
      do: {:ok, :completed, %{"status" => "disputed", "comment" => "off-topic", "model" => "m"}}

    def check_job_status("vote:" <> _),
      do: {:ok, :completed, %{"correct_answer" => "for", "comment" => "c", "model" => "m"}}
  end

  defmodule UnverifiableQuoteVerifier do
    @behaviour YouCongress.Verifications.Verifier
    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_unverifiable", "comment" => "c", "model" => "m"}}
  end

  defmodule MessageVerifier do
    @behaviour YouCongress.Verifications.Verifier
    def submit(subject_type, %{id: id}) do
      send(
        Application.get_env(:you_congress, :verification_test_pid),
        {:submitted, subject_type, id}
      )

      {:ok, "#{subject_type}:#{id}"}
    end

    def check_job_status("vote:" <> _),
      do: {:ok, :completed, %{"correct_answer" => "for", "comment" => "c", "model" => "m"}}

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}
  end

  defmodule CapturingVoteVerifier do
    @behaviour YouCongress.Verifications.Verifier

    def submit(:vote, vote) do
      send(
        Application.get_env(:you_congress, :verification_test_pid),
        {:submitted_vote, vote.id, vote.opinion_id, vote.opinion && vote.opinion.content}
      )

      {:ok, "vote:#{vote.id}:#{vote.opinion_id}"}
    end

    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("vote:" <> _),
      do: {:ok, :completed, %{"correct_answer" => "for", "comment" => "c", "model" => "m"}}

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}
  end

  defmodule CorrectingQuoteVerifier do
    @behaviour YouCongress.Verifications.Verifier

    @correct_content "Correct quote text"
    @correct_source_url "https://example.com/correct-quote"
    @correct_author_name "Correct Quote Author"

    def submit(:quote, %{id: id, content: "Wrong quote text"}) do
      notify({:submitted_quote, :wrong, id})
      {:ok, "quote:#{id}:wrong"}
    end

    def submit(:quote, %{id: id}) do
      notify({:submitted_quote, :corrected, id})
      {:ok, "quote:#{id}:corrected"}
    end

    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("quote:" <> rest) do
      if String.ends_with?(rest, ":wrong") do
        {:ok, :completed,
         %{
           "status" => "disputed",
           "comment" => "Stored quote metadata was wrong",
           "model" => "m",
           "correction" => %{
             "content" => @correct_content,
             "source_url" => @correct_source_url,
             "date" => "2024-05",
             "date_precision" => "month",
             "author" => %{
               "name" => @correct_author_name,
               "bio" => "AI safety researcher",
               "wikipedia_url" => "https://en.wikipedia.org/wiki/Correct_Quote_Author",
               "twitter_username" => "correctquoteauthor"
             }
           }
         }}
      else
        {:ok, :completed, %{"status" => "ai_verified", "comment" => "corrected", "model" => "m"}}
      end
    end

    def check_job_status("vote:" <> _),
      do: {:ok, :completed, %{"correct_answer" => "for", "comment" => "c", "model" => "m"}}

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}

    def correct_content, do: @correct_content
    def correct_source_url, do: @correct_source_url
    def correct_author_name, do: @correct_author_name

    defp notify(message) do
      if pid = Application.get_env(:you_congress, :verification_test_pid) do
        send(pid, message)
      end
    end
  end

  defmodule LoopingCorrectionVerifier do
    @behaviour YouCongress.Verifications.Verifier

    def submit(subject_type, subject), do: submit(subject_type, subject, [])

    def submit(:quote, %{id: id, content: content}, opts) do
      attempts = Keyword.fetch!(opts, :correction_attempts)
      allow_correction? = Keyword.fetch!(opts, :allow_quote_correction?)

      notify({:loop_quote_submitted, attempts, allow_correction?, content})

      {:ok, "loop_quote:#{id}:#{attempts}:#{allow_correction?}"}
    end

    def submit(subject_type, %{id: id}, _opts), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("loop_quote:" <> rest) do
      [_id, attempts, allow_correction?] = String.split(rest, ":", parts: 3)
      attempts = String.to_integer(attempts)
      correction_number = attempts + 1

      result = %{
        "status" => if(allow_correction? == "true", do: "disputed", else: "ai_verified"),
        "comment" => "loop #{correction_number}",
        "model" => "m",
        "correction" => correction(correction_number)
      }

      {:ok, :completed, result}
    end

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}

    defp correction(number) do
      %{
        "content" => "Corrected quote #{number}",
        "source_url" => "https://example.com/corrected-quote-#{number}",
        "date" => "2024",
        "date_precision" => "year",
        "author" => %{
          "name" => "Loop Correction Author",
          "bio" => "AI policy expert",
          "wikipedia_url" => "https://en.wikipedia.org/wiki/Loop_Correction_Author",
          "twitter_username" => "loopcorrection"
        }
      }
    end

    defp notify(message) do
      if pid = Application.get_env(:you_congress, :verification_test_pid) do
        send(pid, message)
      end
    end
  end

  defmodule MultiAuthorCorrectionVerifier do
    @behaviour YouCongress.Verifications.Verifier

    def submit(:quote, %{id: id, content: "Wrong multi-person quote"}) do
      {:ok, "multi_author:#{id}:people"}
    end

    def submit(:quote, %{id: id, content: "Wrong organisation quote"}) do
      {:ok, "multi_author:#{id}:organisation"}
    end

    def submit(:quote, %{id: id, content: "Wrong declaration quote"}) do
      {:ok, "multi_author:#{id}:declaration"}
    end

    def submit(:quote, %{id: id}), do: {:ok, "multi_author:#{id}:verified"}
    def submit(subject_type, %{id: id}), do: {:ok, "#{subject_type}:#{id}"}

    def check_job_status("multi_author:" <> rest) do
      [_id, type] = String.split(rest, ":", parts: 2)

      case type do
        "people" ->
          correction("Alice Smith and Bob Jones", "https://en.wikipedia.org/wiki/Alice_Smith")

        "organisation" ->
          correction(
            "Research and Development Corporation",
            "https://en.wikipedia.org/wiki/Research_and_Development_Corporation"
          )

        "declaration" ->
          correction("AI Safety and Human Values Declaration", "")

        "verified" ->
          {:ok, :completed,
           %{"status" => "ai_verified", "comment" => "corrected", "model" => "m"}}
      end
    end

    def check_job_status(_),
      do: {:ok, :completed, %{"status" => "ai_verified", "comment" => "c", "model" => "m"}}

    defp correction(author_name, wikipedia_url) do
      {:ok, :completed,
       %{
         "status" => "disputed",
         "comment" => "author correction",
         "model" => "m",
         "correction" => %{
           "content" => "Corrected author quote",
           "source_url" => "https://example.com/corrected-author-quote",
           "date" => "2024",
           "date_precision" => "year",
           "author" => %{
             "name" => author_name,
             "bio" => "AI policy author",
             "wikipedia_url" => wikipedia_url,
             "twitter_username" => "authorcorrection"
           }
         }
       }}
    end
  end

  # --- Helpers ----------------------------------------------------------------

  defp put_env_restore(key, value) do
    original = Application.fetch_env(:you_congress, key)
    Application.put_env(:you_congress, key, value)

    on_exit(fn ->
      case original do
        {:ok, original_value} -> Application.put_env(:you_congress, key, original_value)
        :error -> Application.delete_env(:you_congress, key)
      end
    end)
  end

  defp use_verifier(module) do
    put_env_restore(:quote_verifier_implementation, module)
  end

  defp set_system_user do
    user = user_fixture()
    put_env_restore(:verification_user_id, user.id)
    user
  end

  defp without_system_user(fun) do
    original = Application.fetch_env(:you_congress, :verification_user_id)
    Application.delete_env(:you_congress, :verification_user_id)

    try do
      fun.()
    after
      case original do
        {:ok, original_value} ->
          Application.put_env(:you_congress, :verification_user_id, original_value)

        :error ->
          Application.delete_env(:you_congress, :verification_user_id)
      end
    end
  end

  defp build_quote_with_vote(answer \\ :against) do
    author = author_fixture()
    user = user_fixture(%{author_id: author.id})
    statement = statement_fixture()

    opinion =
      without_system_user(fn ->
        {:ok, %{opinion: opinion}} =
          Opinions.create_opinion(%{
            content: "A real sourced quote",
            source_url: "https://example.com/quote",
            twin: false,
            author_id: author.id,
            user_id: user.id
          })

        opinion
      end)

    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement, user.id)

    {:ok, vote} =
      Votes.create_vote(%{
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: answer
      })

    %{opinion: opinion, statement: statement, vote: vote}
  end

  defp verify_quote(opinion_id) do
    %{"subject" => "quote", "id" => opinion_id}
    |> VerificationWorker.new()
    |> Oban.insert()
  end

  defp flush_submitted_votes do
    receive do
      {:submitted_vote, _vote_id, _opinion_id, _content} -> flush_submitted_votes()
    after
      0 -> :ok
    end
  end

  # --- Tests ------------------------------------------------------------------

  describe "full cascade" do
    test "verifies quote, relevance and vote, correcting the vote answer" do
      use_verifier(PositiveVerifier)
      set_system_user()
      %{opinion: opinion, statement: statement, vote: vote} = build_quote_with_vote(:against)

      verify_quote(opinion.id)

      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified

      os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)
      assert os.verification_status == :ai_verified

      reloaded = Votes.get_vote!(vote.id)
      assert reloaded.verification_status == :ai_verified
      # The quote supports "for", so the vote answer is corrected from :against.
      assert reloaded.answer == :for
    end

    test "verifies a vote using the cascaded quote, not another quote on the same statement" do
      use_verifier(CapturingVoteVerifier)
      put_env_restore(:verification_test_pid, self())
      set_system_user()

      author = author_fixture()
      user = user_fixture(%{author_id: author.id})
      statement = statement_fixture()

      {:ok, %{opinion: first_quote}} =
        Opinions.create_opinion(%{
          content: "The public should deliberate on AI value alignment.",
          source_url: "https://example.com/first",
          twin: false,
          author_id: author.id,
          user_id: user.id
        })

      {:ok, %{opinion: dummy_quote}} =
        Opinions.create_opinion(%{
          content: "aaasd wewe wwe",
          source_url: "https://example.com/dummy",
          twin: false,
          author_id: author.id,
          user_id: user.id
        })

      {:ok, _} = Opinions.add_opinion_to_statement(first_quote, statement, user.id)
      {:ok, _} = Opinions.add_opinion_to_statement(dummy_quote, statement, user.id)

      {:ok, vote} =
        Votes.create_vote(%{
          author_id: author.id,
          statement_id: statement.id,
          opinion_id: dummy_quote.id,
          answer: :against
        })

      flush_submitted_votes()
      verify_quote(first_quote.id)

      vote_id = vote.id
      first_quote_id = first_quote.id

      assert_received {:submitted_vote, ^vote_id, ^first_quote_id,
                       "The public should deliberate on AI value alignment."}

      [vote_verification] =
        VoteVerifications.list_verifications(vote_id: vote.id, opinion_id: first_quote.id)

      assert vote_verification.opinion_id == first_quote.id
      assert VoteVerifications.status_for_vote_opinion(vote.id, first_quote.id) == :ai_verified

      reloaded = Votes.get_vote!(vote.id)
      assert reloaded.opinion_id == dummy_quote.id
      assert reloaded.verification_status == nil
    end
  end

  describe "automatic_verifications feature flag" do
    test "records quote verification without cascading to relevance when disabled" do
      use_verifier(PositiveVerifier)
      set_system_user()
      put_env_restore(:feature_flags, %{automatic_verifications: false})
      %{opinion: opinion, statement: statement, vote: vote} = build_quote_with_vote(:against)

      verify_quote(opinion.id)

      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified

      os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)
      assert os.verification_status == nil

      reloaded = Votes.get_vote!(vote.id)
      assert reloaded.verification_status == nil
      assert reloaded.answer == :against
    end

    test "records relevance verification without cascading to vote when disabled" do
      system_user = set_system_user()
      put_env_restore(:feature_flags, %{automatic_verifications: false})
      %{opinion: opinion, statement: statement, vote: vote} = build_quote_with_vote(:against)

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: system_user.id,
          status: :ai_verified,
          comment: "Authentic",
          model: "m"
        })

      os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

      assert :ok =
               AIVerifications.record_and_cascade("relevance", os.id, %{
                 "status" => "ai_verified",
                 "comment" => "Relevant",
                 "model" => "m"
               })

      assert OpinionsStatements.get_opinion_statement(opinion.id, statement.id).verification_status ==
               :ai_verified

      assert VoteVerifications.list_verifications(vote_id: vote.id) == []

      reloaded = Votes.get_vote!(vote.id)
      assert reloaded.verification_status == nil
      assert reloaded.answer == :against
    end
  end

  describe "disputed relevance" do
    test "unlinks the quote from the statement" do
      use_verifier(DisputedRelevanceVerifier)
      set_system_user()
      %{opinion: opinion, statement: statement, vote: vote} = build_quote_with_vote()

      verify_quote(opinion.id)

      # Quote itself is still verified...
      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified
      # ...but the disputed relevance removed the link (and its dependent vote).
      assert OpinionsStatements.get_opinion_statement(opinion.id, statement.id) == nil
      assert Votes.get_vote(vote.id) == nil
    end
  end

  describe "gating" do
    test "an unverifiable quote does not cascade to relevance or votes" do
      use_verifier(UnverifiableQuoteVerifier)
      set_system_user()
      %{opinion: opinion, statement: statement, vote: vote} = build_quote_with_vote()

      verify_quote(opinion.id)

      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_unverifiable

      assert OpinionsStatements.get_opinion_statement(opinion.id, statement.id).verification_status ==
               nil

      assert Votes.get_vote!(vote.id).verification_status == nil
    end
  end

  describe "quote corrections" do
    test "applies a source_text correction for a non-web quote with no URL" do
      use_verifier(PositiveVerifier)
      set_system_user()

      author = author_fixture(%{name: "Book Author"})
      user = user_fixture(%{author_id: author.id})

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "A quote from a book.",
              source_url: nil,
              source_text: "Wrong citation, p. 1",
              twin: false,
              author_id: author.id,
              user_id: user.id
            })

          opinion
        end)

      result = %{
        "status" => "disputed",
        "comment" => "Citation was wrong",
        "model" => "m",
        "correction" => %{
          "content" => "A quote from a book.",
          "source_url" => nil,
          "source_text" => "Sapiens, Y. N. Harari, Harper, 2015, p. 241: the passage.",
          "date" => nil,
          "date_precision" => nil,
          "author" => nil
        }
      }

      assert :ok = AIVerifications.record_and_cascade("quote", opinion.id, result)

      reloaded = Opinions.get_opinion!(opinion.id)

      assert reloaded.source_url == nil
      assert reloaded.source_text == "Sapiens, Y. N. Harari, Harper, 2015, p. 241: the passage."
      assert reloaded.verification_status == :ai_verified
    end

    test "updates corrected quote fields and re-verifies the corrected opinion" do
      use_verifier(CorrectingQuoteVerifier)
      put_env_restore(:verification_test_pid, self())
      set_system_user()

      wrong_author = author_fixture(%{name: "Wrong Quote Author"})
      user = user_fixture(%{author_id: wrong_author.id})
      statement = statement_fixture()

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "Wrong quote text",
              source_url: "https://example.com/wrong-quote",
              date: "2020",
              twin: false,
              author_id: wrong_author.id,
              user_id: user.id
            })

          opinion
        end)

      {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement, user.id)

      {:ok, vote} =
        Votes.create_vote(%{
          author_id: wrong_author.id,
          statement_id: statement.id,
          opinion_id: opinion.id,
          answer: :against
        })

      verify_quote(opinion.id)

      assert_received {:submitted_quote, :wrong, _}
      assert_received {:submitted_quote, :corrected, _}

      reloaded = Opinions.get_opinion!(opinion.id, preload: [:author])

      assert reloaded.content == CorrectingQuoteVerifier.correct_content()
      assert reloaded.source_url == CorrectingQuoteVerifier.correct_source_url()
      assert reloaded.date == ~D[2024-05-01]
      assert reloaded.date_precision == :month
      assert reloaded.author.name == CorrectingQuoteVerifier.correct_author_name()
      assert reloaded.verification_status == :ai_verified

      refute Enum.any?(
               Verifications.list_verifications(opinion_id: opinion.id),
               &(&1.status == :disputed)
             )

      reloaded_vote = Votes.get_vote!(vote.id)

      assert reloaded_vote.author_id == reloaded.author_id
      assert reloaded_vote.answer == :for
      assert reloaded_vote.verification_status == :ai_verified
    end

    test "stops applying corrections on the third quote verification" do
      put_env_restore(:verification_test_pid, self())

      wrong_author = author_fixture(%{name: "Loop Wrong Author"})
      user = user_fixture(%{author_id: wrong_author.id})

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "Wrong quote text",
              source_url: "https://example.com/loop-wrong-quote",
              date: "2020",
              twin: false,
              author_id: wrong_author.id,
              user_id: user.id
            })

          opinion
        end)

      use_verifier(LoopingCorrectionVerifier)
      set_system_user()

      verify_quote(opinion.id)

      assert_received {:loop_quote_submitted, 0, true, "Wrong quote text"}
      assert_received {:loop_quote_submitted, 1, true, "Corrected quote 1"}
      assert_received {:loop_quote_submitted, 2, false, "Corrected quote 2"}
      refute_received {:loop_quote_submitted, 3, _, _}

      reloaded = Opinions.get_opinion!(opinion.id, preload: [:author])

      assert reloaded.content == "Corrected quote 2"
      assert reloaded.source_url == "https://example.com/corrected-quote-2"
      assert reloaded.author.name == "Loop Correction Author"
      assert reloaded.verification_status == :ai_verified

      [verification] = Verifications.list_verifications(opinion_id: opinion.id)
      assert verification.status == :ai_verified
    end

    test "disputes a quote when author correction has multiple individual people" do
      use_verifier(MultiAuthorCorrectionVerifier)
      set_system_user()

      author = author_fixture(%{name: "Wrong Multi Author"})
      user = user_fixture(%{author_id: author.id})

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "Wrong multi-person quote",
              source_url: "https://example.com/wrong-multi-person",
              twin: false,
              author_id: author.id,
              user_id: user.id
            })

          opinion
        end)

      verify_quote(opinion.id)

      reloaded = Opinions.get_opinion!(opinion.id, preload: [:author])

      assert reloaded.author.name == "Wrong Multi Author"
      assert reloaded.verification_status == :disputed
      refute Authors.get_author_by(name: "Alice Smith and Bob Jones")

      [verification] = Verifications.list_verifications(opinion_id: opinion.id)
      assert verification.status == :disputed
      assert verification.comment =~ "multiple individual authors"
    end

    test "keeps an organisation author name that contains and" do
      use_verifier(MultiAuthorCorrectionVerifier)
      set_system_user()

      author = author_fixture(%{name: "Wrong Organisation Author"})
      user = user_fixture(%{author_id: author.id})

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "Wrong organisation quote",
              source_url: "https://example.com/wrong-organisation",
              twin: false,
              author_id: author.id,
              user_id: user.id
            })

          opinion
        end)

      verify_quote(opinion.id)

      reloaded = Opinions.get_opinion!(opinion.id, preload: [:author])

      assert reloaded.author.name == "Research and Development Corporation"
    end

    test "keeps a declaration title author name that contains and" do
      use_verifier(MultiAuthorCorrectionVerifier)
      set_system_user()

      author = author_fixture(%{name: "Wrong Declaration Author"})
      user = user_fixture(%{author_id: author.id})

      opinion =
        without_system_user(fn ->
          {:ok, %{opinion: opinion}} =
            Opinions.create_opinion(%{
              content: "Wrong declaration quote",
              source_url: "https://example.com/wrong-declaration",
              twin: false,
              author_id: author.id,
              user_id: user.id
            })

          opinion
        end)

      verify_quote(opinion.id)

      reloaded = Opinions.get_opinion!(opinion.id, preload: [:author])

      assert reloaded.author.name == "AI Safety and Human Values Declaration"
      assert reloaded.verification_status == :ai_verified
    end
  end

  describe "update hook" do
    test "re-verifies only when quote identity or evidence fields change" do
      use_verifier(MessageVerifier)
      put_env_restore(:verification_test_pid, self())

      author = author_fixture()
      other_author = author_fixture()
      user = user_fixture(%{author_id: author.id})

      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "original",
          source_url: "https://example.com/q",
          twin: false,
          author_id: author.id,
          user_id: user.id
        })

      # The create itself submits a quote verification.
      assert_received {:submitted, :quote, _}

      {:ok, opinion} = Opinions.update_opinion(opinion, %{likes_count: 3})
      refute_received {:submitted, :quote, _}

      {:ok, opinion} = Opinions.update_opinion(opinion, %{source_url: "https://example.com/q2"})
      assert_received {:submitted, :quote, _}

      {:ok, opinion} = Opinions.update_opinion(opinion, %{content: "changed"})
      assert_received {:submitted, :quote, _}

      {:ok, opinion} = Opinions.update_opinion(opinion, %{date: "2024-02"})
      assert_received {:submitted, :quote, _}

      {:ok, _opinion} = Opinions.update_opinion(opinion, %{author_id: other_author.id})
      assert_received {:submitted, :quote, _}
    end

    test "does not re-verify quote updates when automatic verifications are disabled" do
      use_verifier(MessageVerifier)
      put_env_restore(:verification_test_pid, self())
      put_env_restore(:feature_flags, %{automatic_verifications: false})

      author = author_fixture()
      user = user_fixture(%{author_id: author.id})

      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "original",
          source_url: "https://example.com/q",
          twin: false,
          author_id: author.id,
          user_id: user.id
        })

      refute_received {:submitted, :quote, _}

      {:ok, _opinion} = Opinions.update_opinion(opinion, %{source_url: "https://example.com/q2"})
      refute_received {:submitted, :quote, _}
    end

    test "does not re-verify when the author edits and endorses their own quote" do
      use_verifier(MessageVerifier)
      put_env_restore(:verification_test_pid, self())

      user = user_fixture()

      {:ok, %{opinion: opinion}} =
        Opinions.create_opinion(%{
          content: "original",
          source_url: "https://example.com/q",
          twin: false,
          author_id: user.author_id,
          user_id: user.id
        })

      # The create itself still submits a quote verification.
      assert_received {:submitted, :quote, _}

      assert {:ok, updated} =
               Opinions.update_opinion(
                 opinion,
                 %{content: "author corrected wording"},
                 actor_user: user
               )

      assert updated.verification_status == :endorsed
      refute_received {:submitted, :quote, _}
    end
  end
end
