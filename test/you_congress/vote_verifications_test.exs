defmodule YouCongress.VoteVerificationsTest do
  use YouCongress.DataCase

  alias YouCongress.VoteVerifications
  alias YouCongress.VoteVerifications.VoteVerification
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.OpinionsStatements
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongress.Votes.Vote

  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.AccountsFixtures

  # A vote backed by a quote, with authenticity + relevance both verified so the
  # progressive vote gate is satisfied.
  defp verified_vote_fixture do
    user = user_fixture()
    author = author_fixture()
    statement = statement_fixture()
    opinion = opinion_fixture(%{author_id: author.id, user_id: user.id})
    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)

    {:ok, vote} =
      Votes.create_vote(%{
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: :for
      })

    verify_quote(opinion, user)
    verify_relevance(opinion, statement, user)

    %{vote: vote, opinion: opinion, statement: statement, user: user}
  end

  # Same setup, but no prerequisites verified yet.
  defp unverified_vote_fixture do
    user = user_fixture()
    author = author_fixture()
    statement = statement_fixture()
    opinion = opinion_fixture(%{author_id: author.id, user_id: user.id})
    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)

    {:ok, vote} =
      Votes.create_vote(%{
        author_id: author.id,
        statement_id: statement.id,
        opinion_id: opinion.id,
        answer: :for
      })

    %{vote: vote, opinion: opinion, statement: statement, user: user}
  end

  defp verify_quote(opinion, user) do
    {:ok, _} =
      Verifications.create_verification(%{
        opinion_id: opinion.id,
        user_id: user.id,
        status: :verified,
        comment: "Authentic"
      })
  end

  defp verify_relevance(opinion, statement, user) do
    os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)

    {:ok, _} =
      OpinionStatementVerifications.create_verification(%{
        opinion_statement_id: os.id,
        user_id: user.id,
        status: :verified,
        comment: "Relevant"
      })
  end

  defp vote(vote, user, status, comment, model \\ "human") do
    VoteVerifications.create_verification(%{
      vote_id: vote.id,
      user_id: user.id,
      status: status,
      comment: comment,
      model: model
    })
  end

  defp reload_vote_status(vote_id), do: Repo.get!(Vote, vote_id).verification_status

  describe "create_verification/1" do
    test "creates a verification and caches the status on the vote" do
      %{vote: v, user: user} = verified_vote_fixture()

      assert {:ok, %VoteVerification{} = ver} = vote(v, user, :verified, "Answer is correct")
      assert ver.vote_id == v.id
      assert ver.opinion_id == v.opinion_id
      assert reload_vote_status(v.id) == :verified
    end

    test "latest verification wins" do
      %{vote: v, user: user} = verified_vote_fixture()

      {:ok, _} = vote(v, user, :verified, "Correct")
      {:ok, _} = vote(v, user, :disputed, "Wrong answer")

      assert reload_vote_status(v.id) == :disputed
    end

    test "unverified clears the cached status" do
      %{vote: v, user: user} = verified_vote_fixture()

      {:ok, _} = vote(v, user, :verified, "Correct")
      {:ok, _} = vote(v, user, :unverified, "Reset")

      assert reload_vote_status(v.id) == nil
    end

    test "human verification overrides an AI verification" do
      %{vote: v, user: user} = verified_vote_fixture()

      {:ok, _} = vote(v, user, :ai_verified, "AI says correct", "opus-4.6")
      assert reload_vote_status(v.id) == :ai_verified

      {:ok, _} = vote(v, user, :disputed, "Human disagrees")
      assert reload_vote_status(v.id) == :disputed
    end

    test "blocks vote verification while the quote is unverified" do
      %{vote: v, user: user} = unverified_vote_fixture()

      assert {:error, :quote_not_verified} = vote(v, user, :verified, "Correct")
      assert reload_vote_status(v.id) == nil
    end

    test "blocks vote verification while relevance is unverified" do
      %{vote: v, opinion: opinion, user: user} = unverified_vote_fixture()
      verify_quote(opinion, user)

      assert {:error, :relevance_not_verified} = vote(v, user, :verified, "Correct")
      assert reload_vote_status(v.id) == nil
    end

    test "allows clearing the vote with :unverified even when prerequisites are missing" do
      %{vote: v, user: user} = unverified_vote_fixture()

      assert {:ok, _} = vote(v, user, :unverified, "Reset")
    end

    test "a verification stops applying once the vote points to a newer opinion" do
      %{vote: v, statement: statement, user: user} = verified_vote_fixture()

      {:ok, _} = vote(v, user, :verified, "Correct for this opinion")
      assert reload_vote_status(v.id) == :verified

      # The author posts a newer opinion on the same statement; the vote moves to it.
      new_opinion =
        opinion_fixture(%{author_id: v.author_id, user_id: user.id})

      {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(new_opinion, statement, user.id)
      {:ok, _} = Votes.update_vote(v, %{opinion_id: new_opinion.id})

      # Prior verification was against the old opinion, so the cache resets.
      assert reload_vote_status(v.id) == nil

      # Verifying against the new opinion requires its own prerequisites.
      verify_quote(new_opinion, user)
      verify_relevance(new_opinion, statement, user)
      {:ok, _} = vote(v, user, :disputed, "Wrong for the new opinion")

      assert reload_vote_status(v.id) == :disputed
    end

    test "can verify a vote in the context of a non-current quote" do
      user = user_fixture()
      author = author_fixture()
      statement = statement_fixture()

      old_quote = opinion_fixture(%{author_id: author.id, user_id: user.id})
      current_quote = opinion_fixture(%{author_id: author.id, user_id: user.id})

      {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(old_quote, statement, user.id)
      {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(current_quote, statement, user.id)

      {:ok, vote} =
        Votes.create_vote(%{
          author_id: author.id,
          statement_id: statement.id,
          opinion_id: current_quote.id,
          answer: :for
        })

      verify_quote(old_quote, user)
      verify_relevance(old_quote, statement, user)

      assert {:ok, verification} =
               VoteVerifications.create_verification(%{
                 vote_id: vote.id,
                 opinion_id: old_quote.id,
                 user_id: user.id,
                 status: :verified,
                 comment: "Correct for the old quote"
               })

      assert verification.opinion_id == old_quote.id
      assert VoteVerifications.status_for_vote_opinion(vote.id, old_quote.id) == :verified
      assert reload_vote_status(vote.id) == nil
    end

    test "requires all fields" do
      %{vote: v} = verified_vote_fixture()

      assert {:error, %Ecto.Changeset{}} =
               VoteVerifications.create_verification(%{vote_id: v.id})
    end
  end
end
