defmodule YouCongress.VerificationsTest do
  use YouCongress.DataCase

  alias YouCongress.Verifications
  alias YouCongress.Verifications.Verification
  alias YouCongress.Opinions

  import YouCongress.OpinionsFixtures
  import YouCongress.AccountsFixtures

  describe "create_verification/2" do
    test "creates a verification and updates opinion cached status" do
      opinion = opinion_fixture()
      user = admin_fixture()

      attrs = %{
        opinion_id: opinion.id,
        user_id: user.id,
        status: :verified,
        comment: "Looks correct"
      }

      assert {:ok, %Verification{} = verification} =
               Verifications.create_verification(user, attrs)

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
      user = admin_fixture()

      assert {:ok, _} =
               Verifications.create_verification(user, %{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 status: :verified,
                 comment: "First verification"
               })

      assert {:ok, _} =
               Verifications.create_verification(user, %{
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
      user = admin_fixture()

      # First verify
      {:ok, _} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Verified"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :verified

      # Then set to unverified
      {:ok, _} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :unverified,
          comment: "Unverified"
        })

      # Cached status should be nil
      assert Opinions.get_opinion!(opinion.id).verification_status == nil
    end

    test "rejects endorsed status when user is neither the opinion author nor a verifier" do
      opinion = opinion_fixture()
      other_user = user_fixture()

      assert {:error, :only_author_can_endorse} =
               Verifications.create_verification(other_user, %{
                 opinion_id: opinion.id,
                 user_id: other_user.id,
                 status: :endorsed,
                 comment: "Endorsed"
               })
    end

    test "allows endorsed status when user can verify opinions" do
      opinion = opinion_fixture()
      admin = admin_fixture()

      assert {:ok, %Verification{status: :endorsed}} =
               Verifications.create_verification(admin, %{
                 opinion_id: opinion.id,
                 user_id: admin.id,
                 status: :endorsed,
                 comment: "Author endorsed by email"
               })

      assert Opinions.get_opinion!(opinion.id).verification_status == :endorsed
    end

    test "allows endorsed status when user is the opinion author" do
      user = admin_fixture()
      opinion = opinion_fixture(%{author_id: user.author_id, user_id: user.id})

      assert {:ok, %Verification{status: :endorsed}} =
               Verifications.create_verification(user, %{
                 opinion_id: opinion.id,
                 user_id: user.id,
                 status: :endorsed,
                 comment: "I said this"
               })
    end

    test "requires all fields" do
      admin = admin_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Verifications.create_verification(admin, %{})
    end

    test "AI verification updates opinion cached status to ai_verified" do
      opinion = opinion_fixture()
      user = admin_fixture()

      {:ok, verification} =
        Verifications.create_ai_verification(user, %{
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
      user = admin_fixture()

      {:ok, verification} =
        Verifications.create_ai_verification(user, %{
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
      user = admin_fixture()

      # First: AI verification
      {:ok, _} =
        Verifications.create_ai_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :ai_verified,
          comment: "AI verified",
          model: "opus-4.6"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :ai_verified

      # Then: human verification
      {:ok, _} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Human verified"
        })

      assert Opinions.get_opinion!(opinion.id).verification_status == :verified
    end

    test "defaults model to human" do
      opinion = opinion_fixture()
      user = admin_fixture()

      {:ok, verification} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Test"
        })

      assert verification.model == "human"
    end

    test "rejects non-verifier roles and does not trust a forged user id" do
      opinion = opinion_fixture()
      admin = admin_fixture()

      for role <- ["user", "creator", "blocked", "spam"] do
        user = user_fixture(%{role: role})

        assert {:error, :forbidden} =
                 Verifications.create_verification(user, %{
                   opinion_id: opinion.id,
                   user_id: admin.id,
                   status: :verified,
                   model: "forged-model"
                 })
      end

      assert Verifications.list_verifications(opinion_id: opinion.id) == []
    end

    test "rejects AI-labelled writes from an ordinary actor" do
      opinion = opinion_fixture()
      user = user_fixture()

      assert {:error, :forbidden} =
               Verifications.create_ai_verification(user, %{
                 opinion_id: opinion.id,
                 status: :ai_verified,
                 model: "forged-model"
               })
    end

    test "derives the verifier and model from the authenticated actor" do
      opinion = opinion_fixture()
      admin = admin_fixture()
      other_admin = admin_fixture()

      assert {:ok, verification} =
               Verifications.create_verification(admin, %{
                 opinion_id: opinion.id,
                 user_id: other_admin.id,
                 status: :verified,
                 model: "forged-model"
               })

      assert verification.user_id == admin.id
      assert verification.model == "human"
    end

    test "human callers cannot create AI-labelled verification states" do
      opinion = opinion_fixture()
      admin = admin_fixture()

      assert {:error, :invalid_human_status} =
               Verifications.create_verification(admin, %{
                 opinion_id: opinion.id,
                 status: :ai_verified
               })
    end
  end

  describe "list_verifications/1" do
    test "filters by opinion_id" do
      opinion1 = opinion_fixture()
      opinion2 = opinion_fixture()
      user = admin_fixture()

      {:ok, _} =
        Verifications.create_verification(user, %{
          opinion_id: opinion1.id,
          user_id: user.id,
          status: :verified,
          comment: "V1"
        })

      {:ok, _} =
        Verifications.create_verification(user, %{
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
      user = admin_fixture()

      for opinion <- [opinion1, opinion2, opinion3] do
        Verifications.create_verification(user, %{
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
      user = admin_fixture()

      {:ok, _} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "First"
        })

      {:ok, _} =
        Verifications.create_verification(user, %{
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
      user = admin_fixture()

      {:ok, verification} =
        Verifications.create_verification(user, %{
          opinion_id: opinion.id,
          user_id: user.id,
          status: :verified,
          comment: "Test"
        })

      assert Verifications.get_verification!(verification.id).id == verification.id
    end
  end
end
