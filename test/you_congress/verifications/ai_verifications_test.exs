defmodule YouCongress.Verifications.AIVerificationsTest do
  @moduledoc """
  Exercises the automated verification cascade (quote -> relevance -> vote) using
  network-free stub verifiers. Oban runs `:inline` in tests, so enqueuing a
  verification job runs the whole cascade synchronously.
  """
  use YouCongress.DataCase

  alias YouCongress.Opinions
  alias YouCongress.OpinionsStatements
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

  describe "update hook" do
    test "re-verifies only when content or source_url change" do
      use_verifier(MessageVerifier)
      put_env_restore(:verification_test_pid, self())

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

      # The create itself submits a quote verification.
      assert_received {:submitted, :quote, _}

      {:ok, opinion} = Opinions.update_opinion(opinion, %{likes_count: 3})
      refute_received {:submitted, :quote, _}

      {:ok, _opinion} = Opinions.update_opinion(opinion, %{content: "changed"})
      assert_received {:submitted, :quote, _}
    end
  end
end
