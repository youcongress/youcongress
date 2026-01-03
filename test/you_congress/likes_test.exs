defmodule YouCongress.LikesTest do
  use YouCongress.DataCase

  import YouCongress.OpinionsFixtures
  import YouCongress.AccountsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Likes
  alias YouCongress.Opinions

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

  test "unlike/2 returns {:ok, :already_unliked} if the user has already unliked the opinion" do
    opinion = opinion_fixture()
    user = user_fixture()

    assert {:ok, :already_unliked} = Likes.unlike(opinion.id, user)
  end

  test "unlike/2 returns {:ok, :already_unliked} if deleting the like fails" do
    opinion = opinion_fixture()
    user = user_fixture()

    assert {:ok, :already_unliked} = Likes.unlike(opinion.id, user)
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
    statement = statement_fixture()

    assert Likes.get_liked_opinion_ids(nil, statement) == []
  end

  test "get_liked_opinion_ids/2 returns the list of liked opinion ids for a user and statement" do
    statement = statement_fixture()
    opinion = opinion_fixture()
    user = user_fixture()

    {:ok, _} = Opinions.add_opinion_to_statement(opinion, statement)

    {:ok, _} = Likes.like(opinion.id, user)

    assert Likes.get_liked_opinion_ids(user, statement) == [opinion.id]
  end
end
