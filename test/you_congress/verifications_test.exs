defmodule YouCongress.VerificationsTest do
  use YouCongress.DataCase

  alias YouCongress.Verifications
  alias YouCongress.Verifications.Verification
  alias YouCongress.Opinions

  import YouCongress.OpinionsFixtures
  import YouCongress.AccountsFixtures

  describe "create_verification/1" do
    test "creates a verification and updates opinion cached status" do
      opinion = opinion_fixture()
      user = user_fixture()

      attrs = %{
        opinion_id: opinion.id,
        user_id: user.id,
        status: :verified,
        comment: "Looks correct"
      }

      assert {:ok, %Verification{} = verification} = Verifications.create_verification(attrs)
      assert verification.opinion_id == opinion.id
      assert verification.user_id == user.id
      assert verification.status == :verified
      assert verification.comment == "Looks correct"

      # Opinion cached status should be updated
      updated_opinion = Opinions.get_opinion!(opinion.id)
      assert updated_opinion.verification_status == :verified
    end

    test "allows multiple verifications for the same opinion by the same user" do
      opinion = opinion_fixture()
      user = user_fixture()

      assert {:ok, _} =
               Verifications.create_verification(%{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 status: :verified,
                 comment: "First verification"
               })

      assert {:ok, _} =
               Verifications.create_verification(%{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 status: :disputed,
                 comment: "Changed my mind"
               })

      verifications = Verifications.list_verifications(opinion_id: opinion.id)
      assert length(verifications) == 2

      # Cached status should reflect the latest
      updated_opinion = Opinions.get_opinion!(opinion.id)
      assert updated_opinion.verification_status == :disputed
    end

    test "unverified status sets opinion cached status to nil" do
      opinion = opinion_fixture()
      user = user_fixture()

      # First verify
      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Verified"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :verified

      # Then set to unverified
      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :unverified,
          comment: "Unverified"
        })

      # Cached status should be nil
      assert Opinions.get_opinion!(opinion.id).verification_status == nil
    end

    test "rejects endorsed status when user is not the opinion author" do
      opinion = opinion_fixture()
      other_user = user_fixture()

      assert {:error, :only_author_can_endorse} =
               Verifications.create_verification(%{
                 opinion_id: opinion.id,
                 user_id: other_user.id,
                 status: :endorsed,
                 comment: "Endorsed"
               })
    end

    test "allows endorsed status when user is the opinion author" do
      user = user_fixture()
      opinion = opinion_fixture(%{author_id: user.author_id, user_id: user.id})

      assert {:ok, %Verification{status: :endorsed}} =
               Verifications.create_verification(%{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 status: :endorsed,
                 comment: "I said this"
               })
    end

    test "requires all fields" do
      assert {:error, %Ecto.Changeset{}} =
               Verifications.create_verification(%{})
    end

    test "AI verification updates opinion cached status to ai_verified" do
      opinion = opinion_fixture()
      user = user_fixture()

      {:ok, verification} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :ai_verified,
          comment: "AI verified",
          model: "opus-4.6"
        })

      assert verification.model == "opus-4.6"

      # Opinion cached status should be ai_verified
      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified
    end

    test "AI unverifiable status updates cached status to ai_unverifiable" do
      opinion = opinion_fixture()
      user = user_fixture()

      {:ok, verification} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :ai_unverifiable,
          comment: "AI cannot access source",
          model: "opus-4.6"
        })

      assert verification.status == :ai_unverifiable
      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_unverifiable
    end

    test "human verification updates cached status even when AI verification exists" do
      opinion = opinion_fixture()
      user = user_fixture()

      # First: AI verification
      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :ai_verified,
          comment: "AI verified",
          model: "opus-4.6"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified

      # Then: human verification
      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Human verified"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :verified
    end

    test "defaults model to human" do
      opinion = opinion_fixture()
      user = user_fixture()

      {:ok, verification} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Test"
        })

      assert verification.model == "human"
    end
  end

  describe "list_verifications/1" do
    test "filters by opinion_id" do
      opinion1 = opinion_fixture()
      opinion2 = opinion_fixture()
      user = user_fixture()

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion1.id,
          user_id: user.id,
          status: :verified,
          comment: "V1"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion2.id,
          user_id: user.id,
          status: :disputed,
          comment: "V2"
        })

      results = Verifications.list_verifications(opinion_id: opinion1.id)
      assert length(results) == 1
      assert hd(results).opinion_id == opinion1.id
    end

    test "filters by list of opinion_ids" do
      opinion1 = opinion_fixture()
      opinion2 = opinion_fixture()
      opinion3 = opinion_fixture()
      user = user_fixture()

      for opinion <- [opinion1, opinion2, opinion3] do
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "V"
        })
      end

      results = Verifications.list_verifications(opinion_id: [opinion1.id, opinion2.id])
      assert length(results) == 2
    end

    test "supports ordering and limit" do
      opinion = opinion_fixture()
      user = user_fixture()

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "First"
        })

      {:ok, _} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :disputed,
          comment: "Second"
        })

      results =
        Verifications.list_verifications(
          opinion_id: opinion.id,
          order_by: [desc: :id],
          limit: 1
        )

      assert length(results) == 1
      assert hd(results).status == :disputed
    end
  end

  describe "get_verification!/1" do
    test "returns the verification with given id" do
      opinion = opinion_fixture()
      user = user_fixture()

      {:ok, verification} =
        Verifications.create_verification(%{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Test"
        })

      assert Verifications.get_verification!(verification.id).id == verification.id
    end
  end
end
