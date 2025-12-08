defmodule YouCongress.ManifestsTest do
  use YouCongress.DataCase

  alias YouCongress.Manifests
  alias YouCongress.Votes

  import YouCongress.ManifestsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures

  describe "manifests" do
    alias YouCongress.Manifests.Manifest

    test "list_manifests/0 returns all manifests" do
      manifest = manifest_fixture()
      assert Manifests.list_manifests() == [manifest]
    end

    test "get_manifest_by_slug!/1 returns the manifest with given slug" do
      manifest = manifest_fixture()
      assert Manifests.get_manifest_by_slug!(manifest.slug).id == manifest.id
    end

    test "create_manifest/1 with valid data creates a manifest" do
      valid_attrs = %{title: "My Manifest", slug: "my-manifest", active: true}

      assert {:ok, %Manifest{} = manifest} = Manifests.create_manifest(valid_attrs)
      assert manifest.title == "My Manifest"
      assert manifest.slug == "my-manifest"
      assert manifest.active == true
    end
  end

  describe "signing" do
    test "sign_manifest/2 creates signature and votes" do
      user = user_fixture()
      voting1 = voting_fixture()
      voting2 = voting_fixture()

      manifest = manifest_fixture()
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting1.id, body: "P1"})
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting2.id, body: "P2"}) # Linked to same voting? No, different.
      manifest_section_fixture(%{manifest_id: manifest.id, body: "P3"}) # No voting

      assert {:ok, _} = Manifests.sign_manifest(manifest, user)

      assert Manifests.signed?(manifest, user)
      assert Manifests.signatures_count(manifest) == 1

      # Check votes
      vote1 = Votes.get_current_user_vote(voting1.id, user.author_id)
      assert vote1
      assert vote1.answer == :for
      assert vote1.direct == true

      vote2 = Votes.get_current_user_vote(voting2.id, user.author_id)
      assert vote2
      assert vote2.answer == :for
    end

    test "sign_manifest/2 does not overwrite existing votes" do
      user = user_fixture()
      voting = voting_fixture()

      # User already voted Disagree
      Votes.create_vote(%{
        voting_id: voting.id,
        author_id: user.author_id,
        answer: :against,
        direct: true
      })

      manifest = manifest_fixture()
      manifest_section_fixture(%{manifest_id: manifest.id, voting_id: voting.id, body: "P1"})

      assert {:ok, _} = Manifests.sign_manifest(manifest, user)

      # Check vote remains Disagree
      vote = Votes.get_current_user_vote(voting.id, user.author_id)
      assert vote.answer == :against
    end

    test "sign_manifest/2 fails if already signed" do
      user = user_fixture()
      manifest = manifest_fixture()

      assert {:ok, _} = Manifests.sign_manifest(manifest, user)
      assert {:error, :signature, changeset, _} = Manifests.sign_manifest(manifest, user)
      assert "has already been taken" in errors_on(changeset).manifest_id
    end
  end
end
