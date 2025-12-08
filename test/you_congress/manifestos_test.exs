defmodule YouCongress.ManifestosTest do
  use YouCongress.DataCase

  alias YouCongress.Manifestos
  alias YouCongress.Votes

  import YouCongress.ManifestosFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures

  describe "manifestos" do
    alias YouCongress.Manifestos.Manifesto

    test "list_manifestos/0 returns all manifestos" do
      manifesto = manifesto_fixture()
      assert Manifestos.list_manifestos() == [manifesto]
    end

    test "get_manifesto_by_slug!/1 returns the manifesto with given slug" do
      manifesto = manifesto_fixture()
      assert Manifestos.get_manifesto_by_slug!(manifesto.slug).id == manifesto.id
    end

    test "create_manifesto/1 with valid data creates a manifesto" do
      valid_attrs = %{title: "My Manifesto", slug: "my-manifesto", active: true}

      assert {:ok, %Manifesto{} = manifesto} = Manifestos.create_manifesto(valid_attrs)
      assert manifesto.title == "My Manifesto"
      assert manifesto.slug == "my-manifesto"
      assert manifesto.active == true
    end
  end

  describe "signing" do
    test "sign_manifesto/2 creates signature and votes" do
      user = user_fixture()
      voting1 = voting_fixture()
      voting2 = voting_fixture()

      manifesto = manifesto_fixture()
      manifesto_section_fixture(%{manifesto_id: manifesto.id, voting_id: voting1.id, body: "P1"})
      manifesto_section_fixture(%{manifesto_id: manifesto.id, voting_id: voting2.id, body: "P2"}) # Linked to same voting? No, different.
      manifesto_section_fixture(%{manifesto_id: manifesto.id, body: "P3"}) # No voting

      assert {:ok, _} = Manifestos.sign_manifesto(manifesto, user)

      assert Manifestos.signed?(manifesto, user)
      assert Manifestos.signatures_count(manifesto) == 1

      # Check votes
      vote1 = Votes.get_current_user_vote(voting1.id, user.author_id)
      assert vote1
      assert vote1.answer == :for
      assert vote1.direct == true

      vote2 = Votes.get_current_user_vote(voting2.id, user.author_id)
      assert vote2
      assert vote2.answer == :for
    end

    test "sign_manifesto/2 does not overwrite existing votes" do
      user = user_fixture()
      voting = voting_fixture()

      # User already voted Disagree
      Votes.create_vote(%{
        voting_id: voting.id,
        author_id: user.author_id,
        answer: :against,
        direct: true
      })

      manifesto = manifesto_fixture()
      manifesto_section_fixture(%{manifesto_id: manifesto.id, voting_id: voting.id, body: "P1"})

      assert {:ok, _} = Manifestos.sign_manifesto(manifesto, user)

      # Check vote remains Disagree
      vote = Votes.get_current_user_vote(voting.id, user.author_id)
      assert vote.answer == :against
    end

    test "sign_manifesto/2 fails if already signed" do
      user = user_fixture()
      manifesto = manifesto_fixture()

      assert {:ok, _} = Manifestos.sign_manifesto(manifesto, user)
      assert {:error, :signature, changeset, _} = Manifestos.sign_manifesto(manifesto, user)
      assert "has already been taken" in errors_on(changeset).manifesto_id
    end
  end
end
