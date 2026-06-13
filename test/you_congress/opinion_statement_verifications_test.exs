defmodule YouCongress.OpinionStatementVerificationsTest do
  use YouCongress.DataCase

  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.OpinionStatementVerifications.OpinionStatementVerification
  alias YouCongress.OpinionsStatements
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Verifications

  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.AccountsFixtures

  # Builds an opinion-statement link whose quote authenticity is already
  # positive, so the progressive relevance gate is satisfied.
  defp verified_link_fixture do
    user = user_fixture()
    opinion = opinion_fixture(%{user_id: user.id})
    statement = statement_fixture()
    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)
    verify_quote(opinion, user)
    os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)
    {os, opinion, user}
  end

  # Same link, but the quote is NOT verified yet (gate should block relevance).
  defp unverified_link_fixture do
    user = user_fixture()
    opinion = opinion_fixture(%{user_id: user.id})
    statement = statement_fixture()
    {:ok, _} = YouCongress.Opinions.add_opinion_to_statement(opinion, statement, user.id)
    os = OpinionsStatements.get_opinion_statement(opinion.id, statement.id)
    {os, opinion, user}
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

  defp relevance_status(os_id), do: Repo.get!(OpinionStatement, os_id).verification_status

  describe "create_verification/1" do
    test "creates a verification and caches relevance status on the join" do
      {os, _opinion, user} = verified_link_fixture()

      attrs = %{
        opinion_statement_id: os.id,
        user_id: user.id,
        status: :verified,
        comment: "Exactly about this statement"
      }

      assert {:ok, %OpinionStatementVerification{} = v} =
               OpinionStatementVerifications.create_verification(attrs)

      assert v.opinion_statement_id == os.id
      assert v.status == :verified
      assert relevance_status(os.id) == :verified
    end

    test "latest verification wins" do
      {os, _opinion, user} = verified_link_fixture()

      {:ok, _} = relevance(os, user, :verified, "Relevant")
      {:ok, _} = relevance(os, user, :disputed, "Actually off-topic")

      assert length(OpinionStatementVerifications.list_verifications(opinion_statement_id: os.id)) ==
               2

      assert relevance_status(os.id) == :disputed
    end

    test "unverified clears the cached status" do
      {os, _opinion, user} = verified_link_fixture()

      {:ok, _} = relevance(os, user, :verified, "Relevant")
      {:ok, _} = relevance(os, user, :unverified, "Reset")

      assert relevance_status(os.id) == nil
    end

    test "human verification overrides an AI verification" do
      {os, _opinion, user} = verified_link_fixture()

      {:ok, _} = relevance(os, user, :ai_verified, "AI says relevant", "opus-4.6")
      assert relevance_status(os.id) == :ai_verified

      {:ok, _} = relevance(os, user, :disputed, "Human disagrees")
      assert relevance_status(os.id) == :disputed
    end

    test "requires all fields" do
      assert {:error, %Ecto.Changeset{}} =
               OpinionStatementVerifications.create_verification(%{})
    end

    test "blocks relevance verification while the quote is unverified" do
      {os, _opinion, user} = unverified_link_fixture()

      assert {:error, :quote_not_verified} = relevance(os, user, :verified, "Relevant")
      assert relevance_status(os.id) == nil
    end

    test "allows clearing relevance with :unverified even while the quote is unverified" do
      {os, _opinion, user} = unverified_link_fixture()

      assert {:ok, _} = relevance(os, user, :unverified, "Reset")
    end
  end

  defp relevance(os, user, status, comment, model \\ "human") do
    OpinionStatementVerifications.create_verification(%{
      opinion_statement_id: os.id,
      user_id: user.id,
      status: status,
      comment: comment,
      model: model
    })
  end
end
