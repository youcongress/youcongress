defmodule YouCongress.LikesTest do
  use YouCongress.DataCase

  import YouCongress.OpinionsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.VotingsFixtures

  alias YouCongress.Likes

  test "count/1 returns the correct number of likes for an opinion" do
    opinion = opinion_fixture()
    user = user_fixture()

    {:ok, _} = Likes.like(opinion.id, user)

    assert Likes.count(opinion_id: opinion.id) == 1
  end

  test "like/2 creates a new like for an opinion and enqueues a job" do
    opinion = opinion_fixture()
    user = user_fixture()

    {:ok, _} = Likes.like(opinion.id, user)

    assert Likes.count(opinion_id: opinion.id) == 1
  end

  test "unlike/2 deletes the like for an opinion and enqueues a job" do
    opinion = opinion_fixture()
    user = user_fixture()

    {:ok, _} = Likes.like(opinion.id, user)

    assert {:ok, :unliked} = Likes.unlike(opinion.id, user)

    assert Likes.count(opinion_id: opinion.id) == 0
  end

  test "unlike/2 returns {:error, :already_unliked} if the user has already unliked the opinion" do
    opinion = opinion_fixture()
    user = user_fixture()

    assert {:error, :already_unliked} = Likes.unlike(opinion.id, user)
  end

  test "unlike/2 returns {:error, :already_unliked} if deleting the like fails" do
    opinion = opinion_fixture()
    user = user_fixture()

    assert {:error, :already_unliked} = Likes.unlike(opinion.id, user)
  end

  test "get_liked_opinion_ids/1 returns an empty list when user is nil" do
    assert Likes.get_liked_opinion_ids(nil) == []
  end

  test "get_liked_opinion_ids/1 returns the list of liked opinion ids for a user" do
    opinion = opinion_fixture()
    user = user_fixture()

    {:ok, _} = Likes.like(opinion.id, user)

    assert Likes.get_liked_opinion_ids(user) == [opinion.id]
  end

  test "get_liked_opinion_ids/2 returns an empty list when user is nil" do
    voting = voting_fixture()

    assert Likes.get_liked_opinion_ids(nil, voting) == []
  end

  test "get_liked_opinion_ids/2 returns the list of liked opinion ids for a user and voting" do
    voting = voting_fixture()
    opinion = opinion_fixture(%{voting_id: voting.id})
    user = user_fixture()

    {:ok, _} = Likes.like(opinion.id, user)

    assert Likes.get_liked_opinion_ids(user, voting) == [opinion.id]
  end
end
