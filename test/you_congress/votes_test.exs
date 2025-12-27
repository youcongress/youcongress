defmodule YouCongress.VotesTest do
  use YouCongress.DataCase

  import YouCongress.AuthorsFixtures
  import YouCongress.VotingsFixtures
  import YouCongress.VotesFixtures

  import YouCongress.OpinionsFixtures

  alias YouCongress.Votes
  alias YouCongress.Votes.Vote

  describe "votes" do
    @invalid_attrs %{author_id: nil}

    test "list_votes/0 returns all votes" do
      vote = vote_fixture()
      assert Votes.list_votes() == [vote]
    end

    test "get_vote!/1 returns the vote with given id" do
      vote = vote_fixture()
      assert Votes.get_vote!(vote.id) == vote
    end

    test "create_vote/1 with valid data creates a vote" do
      valid_attrs = %{
        opinion_id: opinion_fixture().id,
        author_id: author_fixture().id,
        voting_id: voting_fixture().id,
        answer: :for
      }

      assert {:ok, %Vote{}} = Votes.create_vote(valid_attrs)
    end

    test "create_vote/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Votes.create_vote(@invalid_attrs)
    end

    test "update_vote/2 with valid data updates the vote" do
      vote = vote_fixture()
      opinion = opinion_fixture()
      update_attrs = %{opinion_id: opinion.id}

      assert {:ok, %Vote{} = vote} = Votes.update_vote(vote, update_attrs)
      assert vote.opinion_id == opinion.id
    end

    test "update_vote/2 with invalid data returns error changeset" do
      vote = vote_fixture()
      assert {:error, %Ecto.Changeset{}} = Votes.update_vote(vote, @invalid_attrs)
      assert vote == Votes.get_vote!(vote.id)
    end

    test "delete_vote/1 deletes the vote" do
      vote = vote_fixture()
      assert {:ok, %Vote{}} = Votes.delete_vote(vote)
      assert_raise Ecto.NoResultsError, fn -> Votes.get_vote!(vote.id) end
    end

    test "change_vote/1 returns a vote changeset" do
      vote = vote_fixture()
      assert %Ecto.Changeset{} = Votes.change_vote(vote)
    end

    test "count/0 returns the number of votes" do
      vote_fixture()
      vote_fixture()
      assert Votes.count() == 2
    end

    test "count_by_author_id/1 returns the number of votes by author id" do
      author = author_fixture()
      vote_fixture(author_id: author.id)
      vote_fixture()
      vote_fixture(author_id: author.id)
      assert Votes.count_by_author_id(author.id) == 2
    end
  end
end
