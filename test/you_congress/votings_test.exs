defmodule YouCongress.VotingsTest do
  use YouCongress.DataCase

  alias YouCongress.Votings

  describe "votings" do
    alias YouCongress.Votings.Voting

    import YouCongress.VotingsFixtures

    @invalid_attrs %{title: nil}

    test "list_votings/0 returns all votings" do
      voting = voting_fixture()
      assert Votings.list_votings() == [voting]
    end

    test "get_voting!/1 returns the voting with given id" do
      voting = voting_fixture()
      assert Votings.get_voting!(voting.id) == voting
    end

    test "create_voting/1 with valid data creates a voting" do
      valid_attrs = %{title: "some title"}

      assert {:ok, %Voting{} = voting} = Votings.create_voting(valid_attrs)
      assert voting.title == "some title"
    end

    test "create_voting/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Votings.create_voting(@invalid_attrs)
    end

    test "update_voting/2 with valid data updates the voting" do
      voting = voting_fixture()
      update_attrs = %{title: "some updated title"}

      assert {:ok, %Voting{} = voting} = Votings.update_voting(voting, update_attrs)
      assert voting.title == "some updated title"
    end

    test "update_voting/2 with invalid data returns error changeset" do
      voting = voting_fixture()
      assert {:error, %Ecto.Changeset{}} = Votings.update_voting(voting, @invalid_attrs)
      assert voting == Votings.get_voting!(voting.id)
    end

    test "delete_voting/1 deletes the voting" do
      voting = voting_fixture()
      assert {:ok, %Voting{}} = Votings.delete_voting(voting)
      assert_raise Ecto.NoResultsError, fn -> Votings.get_voting!(voting.id) end
    end

    test "change_voting/1 returns a voting changeset" do
      voting = voting_fixture()
      assert %Ecto.Changeset{} = Votings.change_voting(voting)
    end
  end
end
